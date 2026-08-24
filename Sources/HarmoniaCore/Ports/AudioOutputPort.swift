//
//  AudioOutputPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the abstract audio sink interface used by playback services.
//
public protocol AudioOutputPort: AnyObject {

    /// Invoked when the output can no longer render until it is reconfigured
    /// (host engine reset, output device change, audio server loss).
    ///
    /// Set by the owner after construction; never an initializer parameter.
    /// Implementations must complete their own invalidation sequence before
    /// invoking it — output stopped (`render()` returns 0), configuration
    /// discarded (`start()` throws until `configure(...)` is called again),
    /// and every thread blocked in `render()` released — and must invoke it
    /// with no internal lock held, never from a real-time audio thread, and
    /// never synchronously from inside another port method. While the port
    /// stays invalidated, further detections must not invoke it again; the
    /// next invocation is only permitted after a successful `configure(...)`.
    ///
    /// The port holds the closure strongly — owners must capture themselves
    /// weakly.
    var onInvalidated: (() -> Void)? { get set }

    /// Configures audio output parameters.
    ///
    /// Must be called before `start()`. May be called while stopped to reconfigure.
    /// Must NOT be called while playing.
    ///
    /// Establishes a complete, usable output from scratch: resources left
    /// over from a previous configuration — including an invalidated one —
    /// are discarded and rebuilt, never reused. A successful call clears the
    /// invalidated state. Settings that belong to the rebuilt resources
    /// (notably the `setVolume(_:)` value) may reset to defaults; callers
    /// re-apply them afterwards.
    ///
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz (e.g., 44100.0, 48000.0)
    ///   - channels: Number of audio channels (typically 2 for stereo)
    ///   - framesPerBuffer: Preferred buffer size in frames (hint only)
    /// - Throws:
    ///   - `CoreError.invalidArgument` if parameters are invalid
    ///   - `CoreError.invalidState` if called while playing
    func configure(sampleRate: Double, channels: Int, framesPerBuffer: Int) throws
    
    /// Starts audio output.
    ///
    /// Audio hardware begins consuming data via `render()` calls.
    ///
    /// - Throws:
    ///   - `CoreError.invalidState` if not configured, including when the
    ///     output has been invalidated and not reconfigured since
    ///   - `CoreError.ioError` if audio device cannot be started
    func start() throws
    
    /// Stops audio output.
    ///
    /// Audio hardware stops consuming data.
    /// Must be idempotent (safe to call multiple times).
    /// Must NOT throw.
    func stop()
    
    /// Provides audio data to be played.
    ///
    /// May be called from a real-time audio thread. Implementations MUST:
    /// - NOT allocate memory
    /// - NOT block or wait
    /// - NOT acquire locks (use lock-free data structures)
    /// - Complete in bounded time
    ///
    /// - Parameters:
    ///   - interleavedFloat32: Buffer of Float32 samples, interleaved by channel
    ///   - frameCount: Number of frames in buffer
    /// - Returns: Number of frames actually consumed (may be less than
    ///   frameCount). Returns 0 — without throwing — when the output is
    ///   stopped or invalidated, so a playback loop driving it exits instead
    ///   of spinning or unwinding through an error path.
    /// - Throws: `CoreError` only on an internal failure that prevents the
    ///   frames from being accepted at all
    func render(_ interleavedFloat32: UnsafePointer<Float>, frameCount: Int) throws -> Int

    /// Flushes all queued audio buffers without stopping the engine.
    ///
    /// Stops and immediately restarts the player node to clear any
    /// in-flight buffers. Use before seeking to prevent old audio
    /// from playing after the decoder has moved to a new position.
    func flush()

    /// Sets the output volume.
    ///
    /// - Parameter volume: Target volume in the range 0.0 (silent) to 1.0 (full).
    ///   Values outside this range are clamped by implementations.
    func setVolume(_ volume: Float)
}
