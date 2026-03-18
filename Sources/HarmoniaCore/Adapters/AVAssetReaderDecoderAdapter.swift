//
//  AVAssetReaderDecoderAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Swift 6 compatible using @preconcurrency.
//  Supports macOS 13+ / iOS 16+
//

import Foundation
@preconcurrency import AVFoundation

@available(macOS 13.0, iOS 16.0, *)
public final class AVAssetReaderDecoderAdapter: DecoderPort, @unchecked Sendable {

    private let logger: LoggerPort

    private struct State: Sendable {
        let asset: AVAsset
        let track: AVAssetTrack
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let duration: Double
        let sampleRate: Double
        let channels: Int
        let bitDepth: Int
        // Partial-read state: retains the current CMSampleBuffer and byte offset
        // so that read() can return chunks smaller than a full AVAssetReader packet.
        var pendingBuffer: CMSampleBuffer?
        var pendingByteOffset: Int
        
        init(asset: AVAsset, track: AVAssetTrack, reader: AVAssetReader,
             output: AVAssetReaderTrackOutput, duration: Double, sampleRate: Double,
             channels: Int, bitDepth: Int) {
            self.asset = asset; self.track = track; self.reader = reader
            self.output = output; self.duration = duration; self.sampleRate = sampleRate
            self.channels = channels; self.bitDepth = bitDepth
            self.pendingBuffer = nil; self.pendingByteOffset = 0
        }
    }

    private var handles: [UUID: State] = [:]
    private let lock = NSLock()

    public init(logger: LoggerPort) {
        self.logger = logger
    }

    public func open(url: URL) throws -> DecodeHandle {
        let asset = AVAsset(url: url)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<DecodeHandle, Error>?
        
        Task {
            do {
                let handle = try await self.openAsync(asset: asset, url: url)
                result = .success(handle)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let handle):
            return handle
        case .failure(let error):
            throw error
        case .none:
            throw CoreError.ioError(underlying: NSError(
                domain: "AVAssetReaderDecoderAdapter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open asset"]
            ))
        }
    }
    
    private func openAsync(asset: AVAsset, url: URL) async throws -> DecodeHandle {
        // 1) Load audio track
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw CoreError.notFound("No audio track in asset")
        }

        // 2) Create reader
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw CoreError.decodeError("Failed to create AVAssetReader: \(error.localizedDescription)")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            throw CoreError.invalidState("Cannot add AVAssetReaderTrackOutput")
        }
        reader.add(output)

        // 3) Load duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // 4) Load format descriptions
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let firstDescription = formatDescriptions.first else {
            throw CoreError.decodeError("Missing format description from track")
        }
        
        let formatDescription = firstDescription as! CMFormatDescription
        guard CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio else {
            throw CoreError.decodeError("Format description is not audio type")
        }

        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw CoreError.decodeError("Missing AudioStreamBasicDescription from track")
        }

        let asbd = asbdPointer.pointee

        let state = State(
            asset: asset,
            track: track,
            reader: reader,
            output: output,
            duration: durationSeconds.isFinite ? durationSeconds : 0,
            sampleRate: Double(asbd.mSampleRate),
            channels: Int(asbd.mChannelsPerFrame),
            bitDepth: Int(asbd.mBitsPerChannel == 0 ? 32 : asbd.mBitsPerChannel)
        )  // pendingBuffer/pendingByteOffset default to nil/0

        let id = UUID()
        lock.withLock {
            handles[id] = state
        }

        reader.startReading()
        logger.info("Decoder open: \(url.lastPathComponent) [\(id)]")

        return DecodeHandle(id: id)
    }

    public func read(
        _ handle: DecodeHandle,
        into pcmInterleaved: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) throws -> Int {
        guard maxFrames > 0 else { return 0 }

        return try lock.withLock {
            guard var state = handles[handle.id] else {
                throw CoreError.invalidState("Unknown DecodeHandle")
            }

            let bytesPerFrame = MemoryLayout<Float>.size * state.channels

            // If no pending buffer, fetch the next one from AVAssetReader.
            if state.pendingBuffer == nil {
                switch state.reader.status {
                case .reading, .completed:
                    break
                case .failed:
                    throw CoreError.decodeError(
                        state.reader.error?.localizedDescription ?? "AVAssetReader failed"
                    )
                default:
                    return 0
                }

                guard let next = state.output.copyNextSampleBuffer() else {
                    return 0 // EOF
                }
                state.pendingBuffer = next
                state.pendingByteOffset = 0
            }

            guard let sampleBuffer = state.pendingBuffer,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
            else {
                throw CoreError.decodeError("Missing CMBlockBuffer")
            }

            var lengthAtOffset: Int = 0
            var totalLength: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: state.pendingByteOffset,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )

            guard status == kCMBlockBufferNoErr, let dataPointer else {
                throw CoreError.decodeError("Failed to read PCM data")
            }

            let remainingBytes = totalLength - state.pendingByteOffset
            let remainingFrames = remainingBytes / bytesPerFrame
            let framesToCopy = min(remainingFrames, maxFrames)

            dataPointer.withMemoryRebound(
                to: Float.self,
                capacity: framesToCopy * state.channels
            ) { src in
                pcmInterleaved.update(from: src, count: framesToCopy * state.channels)
            }

            // Advance or clear pending buffer.
            let bytesConsumed = framesToCopy * bytesPerFrame
            if state.pendingByteOffset + bytesConsumed >= totalLength {
                // Current sample buffer fully consumed.
                CMSampleBufferInvalidate(sampleBuffer)
                state.pendingBuffer = nil
                state.pendingByteOffset = 0
            } else {
                state.pendingByteOffset += bytesConsumed
            }

            handles[handle.id] = state
            return framesToCopy
        }
    }

    public func seek(_ handle: DecodeHandle, toSeconds: Double) throws {
        try lock.withLock {
            guard let state = handles[handle.id] else {
                throw CoreError.invalidState("Unknown DecodeHandle")
            }

            let clampedSeconds = max(0, min(toSeconds, state.duration))
            let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)

            // Cancel current reader and clear any pending partial buffer.
            state.reader.cancelReading()
            if let pending = state.pendingBuffer {
                CMSampleBufferInvalidate(pending)
            }

            let reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: state.asset)
            } catch {
                throw CoreError.decodeError("Failed to recreate reader: \(error.localizedDescription)")
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]

            let output = AVAssetReaderTrackOutput(track: state.track, outputSettings: outputSettings)
            guard reader.canAdd(output) else {
                throw CoreError.invalidState("Cannot add output on seek")
            }
            reader.add(output)
            reader.timeRange = CMTimeRange(start: time, duration: .positiveInfinity)
            reader.startReading()

            handles[handle.id] = State(
                asset: state.asset,
                track: state.track,
                reader: reader,
                output: output,
                duration: state.duration,
                sampleRate: state.sampleRate,
                channels: state.channels,
                bitDepth: state.bitDepth
            )
        }
        logger.debug("Decoder seek [\(handle.id)] to \(toSeconds)s")
    }

    public func info(_ handle: DecodeHandle) throws -> StreamInfo {
        let state = try withState(handle)
        return StreamInfo(
            duration: state.duration,
            sampleRate: state.sampleRate,
            channels: state.channels,
            bitDepth: state.bitDepth
        )
    }

    public func close(_ handle: DecodeHandle) {
        let wasRemoved = lock.withLock {
            handles.removeValue(forKey: handle.id) != nil
        }
        
        if wasRemoved {
            logger.debug("Decoder close [\(handle.id)]")
        }
    }

    private func withState(_ handle: DecodeHandle) throws -> State {
        try lock.withLock {
            guard let state = handles[handle.id] else {
                throw CoreError.invalidState("Unknown DecodeHandle")
            }
            return state
        }
    }
}