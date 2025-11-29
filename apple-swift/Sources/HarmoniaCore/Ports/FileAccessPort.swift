//
//  FileAccessPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines sandbox-safe random access file operations for decoders and services.
//

import Foundation

/// Opaque token representing an open file handle.
///
/// Tokens are used to identify open files in a platform-neutral way.
/// Each token is unique and remains valid until `close()` is called.
public struct FileHandleToken: Hashable, Sendable {
    let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

/// Origin for seek operations.
public enum FileSeekOrigin {
    /// Seek relative to the beginning of the file.
    case start
    
    /// Seek relative to the current file position.
    case current
    
    /// Seek relative to the end of the file.
    case end
}

/// Protocol for platform-neutral file I/O operations.
///
/// Provides basic file access with support for random seeking.
/// All implementations must handle sandbox restrictions appropriately
/// (e.g., iOS security-scoped bookmarks, macOS sandboxing).
///
/// - Note: Thread-safe for different tokens. Undefined behavior if called
///         concurrently with the same token.
public protocol FileAccessPort: AnyObject {
    
    /// Opens a file for reading.
    ///
    /// - Parameter url: URL of the file to open
    /// - Returns: Opaque token for subsequent operations
    /// - Throws:
    ///   - `CoreError.notFound` if file does not exist
    ///   - `CoreError.ioError` for permission denied or other I/O errors
    func open(url: URL) throws -> FileHandleToken

    /// Reads up to `count` bytes from the file into `buffer`.
    ///
    /// Reads from the current file position and advances the position
    /// by the number of bytes read.
    ///
    /// - Parameters:
    ///   - token: File handle token from `open()`
    ///   - buffer: Destination buffer (caller-allocated)
    ///   - count: Maximum number of bytes to read
    /// - Returns: Actual number of bytes read (may be less than `count` at EOF).
    ///            Returns 0 at end of file.
    /// - Throws:
    ///   - `CoreError.invalidState` if token is invalid
    ///   - `CoreError.ioError` for I/O errors
    func read(
        _ token: FileHandleToken,
        into buffer: UnsafeMutableRawPointer,
        count: Int
    ) throws -> Int

    /// Seeks to a new position in the file.
    ///
    /// Changes the current file position used by subsequent `read()` calls.
    ///
    /// - Parameters:
    ///   - token: File handle token from `open()`
    ///   - offset: Offset in bytes (interpretation depends on `origin`)
    ///   - origin: Origin for the seek operation
    /// - Throws:
    ///   - `CoreError.invalidState` if token is invalid
    ///   - `CoreError.invalidArgument` if resulting position is invalid
    ///   - `CoreError.ioError` for I/O errors
    ///
    /// Example usage:
    ///
    ///     // Seek to beginning
    ///     try fileAccess.seek(token, offset: 0, origin: .start)
    ///
    ///     // Skip forward 100 bytes
    ///     try fileAccess.seek(token, offset: 100, origin: .current)
    ///
    ///     // Seek to 100 bytes before end
    ///     try fileAccess.seek(token, offset: -100, origin: .end)
    ///
    func seek(
        _ token: FileHandleToken,
        offset: Int64,
        origin: FileSeekOrigin
    ) throws
    
    /// Returns the total size of the file in bytes.
    ///
    /// - Parameter token: File handle token from `open()`
    /// - Returns: File size in bytes
    /// - Throws:
    ///   - `CoreError.invalidState` if token is invalid
    ///   - `CoreError.ioError` for I/O errors
    func size(_ token: FileHandleToken) throws -> Int64

    /// Closes the file and releases associated resources.
    ///
    /// Must be idempotent (safe to call multiple times).
    /// Must NOT throw. After close, the token becomes invalid.
    ///
    /// - Parameter token: File handle token from `open()`
    func close(_ token: FileHandleToken)
}
