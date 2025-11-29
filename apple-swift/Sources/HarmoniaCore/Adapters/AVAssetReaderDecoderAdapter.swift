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
        )

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

        let state = try withState(handle)

        switch state.reader.status {
        case .reading, .completed:
            break
        case .failed:
            if let error = state.reader.error {
                throw CoreError.decodeError(error.localizedDescription)
            } else {
                throw CoreError.decodeError("AVAssetReader failed")
            }
        default:
            return 0
        }

        guard let sampleBuffer = state.output.copyNextSampleBuffer() else {
            return 0 // EOF
        }
        defer { CMSampleBufferInvalidate(sampleBuffer) }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw CoreError.decodeError("Missing CMBlockBuffer")
        }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        if status != kCMBlockBufferNoErr || dataPointer == nil {
            throw CoreError.decodeError("Failed to read PCM data")
        }

        let bytesPerFrame = MemoryLayout<Float>.size * state.channels
        let availableFrames = totalLength / bytesPerFrame
        let framesToCopy = min(availableFrames, maxFrames)

        dataPointer!.withMemoryRebound(
            to: Float.self,
            capacity: framesToCopy * state.channels
        ) { sourcePointer in
            pcmInterleaved.update(
                from: sourcePointer,
                count: framesToCopy * state.channels
            )
        }

        return framesToCopy
    }

    public func seek(_ handle: DecodeHandle, toSeconds: Double) throws {
        let state = try withState(handle)

        let clampedSeconds = max(0, min(toSeconds, state.duration))
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)

        state.reader.cancelReading()

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

        let newState = State(
            asset: state.asset,
            track: state.track,
            reader: reader,
            output: output,
            duration: state.duration,
            sampleRate: state.sampleRate,
            channels: state.channels,
            bitDepth: state.bitDepth
        )

        lock.withLock {
            handles[handle.id] = newState
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
