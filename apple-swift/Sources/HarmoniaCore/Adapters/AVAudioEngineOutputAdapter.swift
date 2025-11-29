//
//  AVAudioEngineOutputAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements AudioOutputPort using AVAudioEngine and AVAudioPlayerNode.
//
//  Note: Constrained to MainActor due to AVFoundation threading model.
//
import Foundation
import AVFoundation

public final class AVAudioEngineOutputAdapter: AudioOutputPort {

    private let logger: LoggerPort

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?
    private var framesPerBuffer: AVAudioFrameCount = 0
    private var preallocatedBuffer: AVAudioPCMBuffer?

    private let lock = NSLock()
    private var isConfigured = false
    private var isStarted = false

    public init(logger: LoggerPort) {
        self.logger = logger
        engine.attach(playerNode)
    }

    public func configure(sampleRate: Double,
                          channels: Int,
                          framesPerBuffer: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        guard sampleRate > 0, channels > 0, framesPerBuffer > 0
        else {
            throw CoreError.invalidArgument("Invalid audio format parameters")
        }

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        ) else {
            throw CoreError.invalidState("Failed to create AVAudioFormat")
        }

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        self.audioFormat = format
        self.framesPerBuffer = AVAudioFrameCount(framesPerBuffer)
        self.isConfigured = true

        // Preallocate buffer for render() to ensure real-time safety.
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: self.framesPerBuffer
        ) else {
            throw CoreError.invalidState("Failed to preallocate AVAudioPCMBuffer")
        }

        buffer.frameLength = self.framesPerBuffer
        self.preallocatedBuffer = buffer
        
        logger.info("Audio configured: \(sampleRate)Hz, \(channels)ch, \(framesPerBuffer) frames/buffer")
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        if isStarted {
            return   // idempotent
        }

        try engine.start()
        playerNode.play()
        isStarted = true
        logger.info("AVAudioEngineOutputAdapter started")
    }

    /// Non-throwing and idempotent stop().
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if isStarted {
            playerNode.stop()
            isStarted = false
        }

        if engine.isRunning {
            engine.pause()
            engine.reset()
            engine.stop()
        }

        logger.debug("AVAudioEngineOutputAdapter stopped")
    }

    /// Real-time safe render:
    /// - No allocation
    /// - Short locking only for reading state
    /// - Returns the number of frames consumed (0 is allowed)
    public func render(
        _ interleavedFloat32: UnsafePointer<Float>,
        frameCount: Int
    ) throws -> Int {
        // Take a snapshot of state under lock.
        lock.lock()
        let isConfiguredSnapshot = isConfigured
        let isStartedSnapshot = isStarted
        let audioFormatSnapshot = audioFormat
        let preallocatedBufferSnapshot = preallocatedBuffer
        lock.unlock()

        // Validate current state.
        guard isConfiguredSnapshot,
              isStartedSnapshot,
              let audioFormat = audioFormatSnapshot,
              let preallocatedBuffer = preallocatedBufferSnapshot
        else {
            logger.warn("render() called in invalid state")
            return 0
        }

        let channelCount = Int(audioFormat.channelCount)
        guard channelCount > 0,
              frameCount > 0
        else {
            return 0
        }

        // Truncate if the caller passes more frames than capacity.
        let framesToCopy = min(frameCount, Int(preallocatedBuffer.frameCapacity))
        
        if frameCount > Int(preallocatedBuffer.frameCapacity) {
            logger.warn("render() truncating \(frameCount) frames to \(preallocatedBuffer.frameCapacity)")
        }
        
        preallocatedBuffer.frameLength = AVAudioFrameCount(framesToCopy)

        // De-interleave input into the preallocated buffer.
        guard let channelData = preallocatedBuffer.floatChannelData else {
            throw CoreError.invalidState("Missing channelData in AVAudioPCMBuffer")
        }

        for frameIndex in 0..<framesToCopy {
            let baseIndex = frameIndex * channelCount
            for channelIndex in 0..<channelCount {
                channelData[channelIndex][frameIndex] =
                    interleavedFloat32[baseIndex + channelIndex]
            }
        }

        // Schedule buffer for playback.
        playerNode.scheduleBuffer(preallocatedBuffer, completionHandler: nil)

        return framesToCopy
    }
}
