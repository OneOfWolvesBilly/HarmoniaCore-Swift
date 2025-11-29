//
//  AudioOutputPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the abstract audio sink interface used by playback services.
//
public protocol AudioOutputPort: AnyObject {
    
    /// Configures audio output parameters.
    ///
    /// Must be called before `start()`. May be called while stopped to reconfigure.
    /// Must NOT be called while playing.
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
    ///   - `CoreError.invalidState` if not configured
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
    /// - Returns: Number of frames actually consumed (may be less than frameCount)
    /// - Throws: `CoreError.invalidState` if output is not started
    func render(_ interleavedFloat32: UnsafePointer<Float>, frameCount: Int) throws -> Int
}
