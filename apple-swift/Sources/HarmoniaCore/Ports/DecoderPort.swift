//
//  DecoderPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Platform-agnostic abstraction for decoding audio streams into
//  interleaved Float32 PCM.
//

import Foundation

public struct DecodeHandle: Hashable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}

public protocol DecoderPort: AnyObject {
    
    /// Opens a decoder for the given URL.
    ///
    /// This is a synchronous operation that initializes the decoder.
    /// For long operations, call this from a background thread.
    ///
    /// - Parameter url: URL of the audio file to decode
    /// - Returns: Opaque handle used for subsequent operations
    /// - Throws:
    ///   - `CoreError.notFound` if file does not exist
    ///   - `CoreError.unsupported` if format is not supported
    ///   - `CoreError.decodeError` if file is corrupted
    ///   - `CoreError.ioError` for other I/O errors
    func open(url: URL) throws -> DecodeHandle
    
    /// Reads up to `maxFrames` of interleaved Float32 samples into `pcmInterleaved`.
    ///
    /// - Parameters:
    ///   - handle: Decode handle from `open()`
    ///   - pcmInterleaved: Buffer to receive decoded samples (caller-allocated)
    ///   - maxFrames: Maximum number of frames to decode
    /// - Returns: Number of frames actually read, or 0 at EOF
    /// - Throws:
    ///   - `CoreError.invalidState` if handle is invalid
    ///   - `CoreError.decodeError` if decoding fails
    ///   - `CoreError.ioError` for I/O errors
    func read(
        _ handle: DecodeHandle,
        into pcmInterleaved: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) throws -> Int
    
    /// Seeks to the approximate time in seconds.
    ///
    /// Implementations may be coarse-grained depending on container support.
    ///
    /// - Parameters:
    ///   - handle: Decode handle from `open()`
    ///   - toSeconds: Target position in seconds
    /// - Throws:
    ///   - `CoreError.invalidState` if handle is invalid
    ///   - `CoreError.invalidArgument` if position is negative or beyond duration
    ///   - `CoreError.unsupported` if seeking is not supported for this format
    func seek(_ handle: DecodeHandle, toSeconds: Double) throws

    /// Returns cached stream info (duration, sample rate, channels, bit depth).
    ///
    /// Must not perform heavy I/O; info is computed during `open()`.
    ///
    /// - Parameter handle: Decode handle from `open()`
    /// - Returns: Stream information structure
    /// - Throws: `CoreError.invalidState` if handle is invalid
    func info(_ handle: DecodeHandle) throws -> StreamInfo

    /// Releases all resources associated with a handle.
    ///
    /// Must be idempotent and non-throwing.
    ///
    /// - Parameter handle: Decode handle from `open()`
    func close(_ handle: DecodeHandle)
}
