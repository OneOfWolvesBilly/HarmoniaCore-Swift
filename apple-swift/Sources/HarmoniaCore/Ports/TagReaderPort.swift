//
//  TagReaderPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the abstraction for reading metadata tags from audio files.
//
import Foundation

public protocol TagReaderPort: AnyObject {

    /// Reads metadata from the given URL.
    ///
    /// This is a synchronous operation. For long operations or to avoid
    /// blocking the main thread, call this from a background thread.
    ///
    /// - Parameter url: URL of the audio file
    /// - Returns: Tag bundle containing extracted metadata
    /// - Throws:
    ///   - `CoreError.notFound` if file does not exist
    ///   - `CoreError.ioError` for I/O errors
    ///   - `CoreError.unsupported` if file format does not support metadata
    func read(url: URL) throws -> TagBundle
}
