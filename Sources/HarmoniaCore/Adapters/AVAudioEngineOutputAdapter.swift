//
//  AVAudioEngineOutputAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  PURPOSE
//  -------
//  Implements AudioOutputPort using AVAudioEngine and AVAudioPlayerNode.
//
//  DESIGN: Double-buffer with DispatchSemaphore backpressure
//  ---------------------------------------------------------
//  AVFoundation is callback-based, not async/await based. The correct
//  pattern is to pre-schedule a fixed number of buffers (2) and use a
//  DispatchSemaphore to block render() until a slot is free.
//
//  IMPORTANT: render() must be called from a plain DispatchQueue thread,
//  NOT from a Swift async Task. Blocking a Swift cooperative thread with
//  DispatchSemaphore.wait() causes thread pool starvation.
//
//  STOP SAFETY
//  -----------
//  When stop() is called, playerNode.stop() cancels all scheduled buffers
//  WITHOUT calling their completion handlers. This means the semaphore
//  will never be signaled for cancelled buffers, causing any thread
//  blocked in render() to hang forever.
//
//  Fix: stop() signals the semaphore enough times to unblock any waiting
//  render() call. render() then detects isStarted == false and returns 0,
//  causing the playback loop to exit cleanly.
//

import Foundation
import AVFoundation

public final class AVAudioEngineOutputAdapter: AudioOutputPort {

    private let logger: LoggerPort

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private let lock = NSLock()
    private var audioFormat: AVAudioFormat?
    private var framesPerBuffer: AVAudioFrameCount = 0
    private var isConfigured = false
    private var isStarted = false

    /// Max concurrent in-flight buffers. Starts at 2 (double-buffer).
    private static let maxInFlight = 2
    private var bufferSemaphore = DispatchSemaphore(value: maxInFlight)

    public init(logger: LoggerPort) {
        self.logger = logger
        engine.attach(playerNode)
    }

    public func configure(sampleRate: Double,
                          channels: Int,
                          framesPerBuffer: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        guard sampleRate > 0, channels > 0, framesPerBuffer > 0 else {
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
        // Fresh semaphore for each session.
        self.bufferSemaphore = DispatchSemaphore(value: Self.maxInFlight)

        logger.info("Audio configured: \(sampleRate)Hz, \(channels)ch, \(framesPerBuffer) frames/buffer")
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isStarted else { return }

        try engine.start()
        playerNode.play()
        isStarted = true
        logger.info("AVAudioEngineOutputAdapter started")
    }

    public func stop() {
        lock.lock()

        guard isStarted else {
            lock.unlock()
            return
        }

        playerNode.stop()
        isStarted = false

        if engine.isRunning {
            engine.pause()
            engine.reset()
            engine.stop()
        }

        // playerNode.stop() cancels scheduled buffers without calling their
        // completion handlers. Signal the semaphore maxInFlight times to
        // unblock any thread blocked in render().
        let semaphore = bufferSemaphore
        lock.unlock()

        for _ in 0..<Self.maxInFlight {
            semaphore.signal()
        }

        logger.debug("AVAudioEngineOutputAdapter stopped")
    }

    /// Flushes all queued buffers by stopping and restarting the player node.
    ///
    /// Does NOT stop the AVAudioEngine. Resets the semaphore to unblock any
    /// thread waiting in render(), then restarts the player node for fresh output.
    public func flush() {
        lock.lock()
        guard isStarted else {
            lock.unlock()
            return
        }
        // Stop player node — cancels all scheduled buffers without callbacks.
        playerNode.stop()
        // Signal semaphore to unblock any thread waiting in render().
        let semaphore = bufferSemaphore
        lock.unlock()

        for _ in 0..<Self.maxInFlight {
            semaphore.signal()
        }

        // Reset semaphore and restart player node.
        lock.lock()
        bufferSemaphore = DispatchSemaphore(value: Self.maxInFlight)
        if isStarted {
            playerNode.play()
        }
        lock.unlock()

        logger.debug("AVAudioEngineOutputAdapter flushed")
    }

    /// Synchronous render with double-buffer backpressure.
    ///
    /// Blocks via DispatchSemaphore if maxInFlight buffers are already scheduled.
    /// Returns 0 immediately if the adapter has been stopped.
    /// Must be called from a DispatchQueue thread, not a Swift async Task.
    public func render(
        _ interleavedFloat32: UnsafePointer<Float>,
        frameCount: Int
    ) throws -> Int {
        lock.lock()
        let configured = isConfigured
        let started = isStarted
        let format = audioFormat
        let capacity = framesPerBuffer
        let semaphore = bufferSemaphore
        lock.unlock()

        guard configured, started, let format else {
            // Either not started or stop() was called — return 0 so the
            // playback loop exits cleanly.
            return 0
        }

        let channelCount = Int(format.channelCount)
        guard channelCount > 0, frameCount > 0 else { return 0 }

        let framesToCopy = min(frameCount, Int(capacity))

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(framesToCopy)
        ) else {
            throw CoreError.invalidState("Failed to allocate AVAudioPCMBuffer")
        }
        buffer.frameLength = AVAudioFrameCount(framesToCopy)

        guard let channelData = buffer.floatChannelData else {
            throw CoreError.invalidState("Missing channelData in AVAudioPCMBuffer")
        }

        for frame in 0..<framesToCopy {
            let base = frame * channelCount
            for ch in 0..<channelCount {
                channelData[ch][frame] = interleavedFloat32[base + ch]
            }
        }

        // Block until a buffer slot is free.
        // If stop() was called, it signals the semaphore to unblock us,
        // and the isStarted check at the top of the next call returns 0.
        semaphore.wait()

        // Re-check isStarted after unblocking — stop() may have fired.
        lock.lock()
        let stillStarted = isStarted
        lock.unlock()

        guard stillStarted else { return 0 }

        playerNode.scheduleBuffer(buffer) {
            semaphore.signal()
        }

        return framesToCopy
    }

    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }
}
