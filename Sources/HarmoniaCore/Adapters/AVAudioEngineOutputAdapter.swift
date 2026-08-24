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
//  INVALIDATION
//  ------------
//  AVAudioEngine can lose the ability to reach the speakers while this
//  adapter still believes it is playing: the engine stops itself on a
//  configuration change (and posts AVAudioEngineConfigurationChange), or a
//  default-output-device change leaves its internal aggregate device stale —
//  isRunning stays true, completion handlers keep firing, no sound comes
//  out, and no notification is guaranteed. Because the stale case is not
//  observable, configure() never reuses an engine: every call discards the
//  current engine and builds a fresh one. The notification, when it does
//  arrive, is handled off-thread (AVFoundation forbids deallocating the
//  engine inside the handler) and reported to the owner via onInvalidated.
//

import Foundation
import AVFoundation

public final class AVAudioEngineOutputAdapter: AudioOutputPort {

    private let logger: LoggerPort

    /// Replaceable: configure() always discards the current engine and
    /// builds a fresh one (see INVALIDATION in the file header).
    private var engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// EQ node spliced between `playerNode` and `engine.mainMixerNode`
    /// during `configure(...)`. When `nil` the chain is direct
    /// (no EQ), preserving the direct-chain behaviour for adapters
    /// constructed without an EQ.
    ///
    /// Typed as the concrete `AVAudioUnitEQAdapter` rather than the
    /// `EQPort` protocol: graph wiring is an adapter-to-adapter
    /// concern between two Apple-specific implementations, not part
    /// of the platform-agnostic Port contract.
    private let eq: AVAudioUnitEQAdapter?

    private let lock = NSLock()
    private var audioFormat: AVAudioFormat?
    private var framesPerBuffer: AVAudioFrameCount = 0
    private var isConfigured = false
    private var isStarted = false

    /// Max concurrent in-flight buffers. Starts at 2 (double-buffer).
    private static let maxInFlight = 2
    private var bufferSemaphore = DispatchSemaphore(value: maxInFlight)

    /// Invalidation callback (AudioOutputPort). Guarded by `lock`; invoked
    /// on `invalidationQueue` with the lock released.
    private var _onInvalidated: (() -> Void)?

    public var onInvalidated: (() -> Void)? {
        get { lock.withLock { _onInvalidated } }
        set { lock.withLock { _onInvalidated = newValue } }
    }

    /// Serial queue the configuration-change notification is hopped onto.
    /// AVFoundation posts on an unspecified thread and forbids deallocating
    /// the engine inside the handler, so the handler itself does no work.
    private let invalidationQueue = DispatchQueue(
        label: "com.harmoniacore.audio-output.invalidation")

    /// Observer token for AVAudioEngineConfigurationChange. Registered once,
    /// for all objects; the handler filters by engine identity. A notification
    /// posted without an object would be invisible to an engine-scoped
    /// observer and would disable invalidation detection entirely.
    private var configObserver: NSObjectProtocol?

    public init(logger: LoggerPort, eq: AVAudioUnitEQAdapter? = nil) {
        self.logger = logger
        self.eq = eq
        engine.attach(playerNode)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let objectID = note.object.map { ObjectIdentifier($0 as AnyObject) }
            self?.invalidationQueue.async { [weak self] in
                self?.handleInvalidation(notificationObjectID: objectID)
            }
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
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

        // Discard the current engine and start from a fresh one. An engine can
        // become unusable without any observable signal (a stale internal
        // aggregate device after a default-output change reports isRunning and
        // fires completion handlers while reaching no speaker), so no engine is
        // ever reused across configurations. The old engine is released here,
        // on the caller's thread — it must not be deallocated inside the
        // configuration-change notification handler.
        playerNode.stop()
        if playerNode.engine === engine {
            engine.detach(playerNode)
        }
        eq?.detach(from: engine)
        engine = AVAudioEngine()
        engine.attach(playerNode)
        if let eq = eq {
            // Splice EQ into the chain: playerNode → eq → mainMixerNode.
            // The EQ adapter handles both connect calls atomically and
            // disconnects any pre-existing playerNode → mainMixerNode
            // connection internally. This is the ONLY place in the
            // codebase where the live audio chain is wired, so EQ
            // control surface mutations now affect actual audio.
            try eq.attach(to: engine,
                          between: playerNode,
                          and: engine.mainMixerNode,
                          format: format)
        } else {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }

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

        guard isConfigured else {
            throw CoreError.invalidState(
                "Audio output is not configured — call configure(...) first")
        }

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
        lock.lock()
        defer { lock.unlock() }
        engine.mainMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }

    /// Runs on `invalidationQueue`. Performs the port-contract invalidation
    /// sequence, then reports to the owner.
    private func handleInvalidation(notificationObjectID: ObjectIdentifier?) {
        lock.lock()

        // Ours if the notification carries the engine this adapter currently
        // owns, or no object at all. Notifications for other engines in the
        // host process are ignored.
        if let notificationObjectID, notificationObjectID != ObjectIdentifier(engine) {
            lock.unlock()
            return
        }

        // Coalesce: already invalidated (or never configured) — the owner was
        // told once; the next report requires a successful configure() first.
        guard isConfigured || isStarted else {
            lock.unlock()
            return
        }

        playerNode.stop()
        isStarted = false
        isConfigured = false

        let semaphore = bufferSemaphore
        let callback = _onInvalidated
        lock.unlock()

        // playerNode.stop() cancels scheduled buffers without invoking their
        // completion handlers; release any thread blocked in render(). It then
        // re-checks isStarted and returns 0.
        for _ in 0..<Self.maxInFlight {
            semaphore.signal()
        }

        logger.info("Audio output invalidated; reconfiguration required")

        // Invoked with no lock held so the handler may call back into this
        // adapter (stop/configure/start/setVolume) re-entrantly.
        callback?()
    }
}
