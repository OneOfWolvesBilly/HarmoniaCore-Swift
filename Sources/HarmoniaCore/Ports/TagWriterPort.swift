//
//  TagWriterPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the abstraction for writing metadata tags to audio files where supported.
//
import Foundation

public protocol TagWriterPort: AnyObject {
    /// Writes tags to the given URL.
    /// - Parameters:
    ///   - url: Target audio file URL.
    ///   - tags: Structured tag bundle to persist.
    /// - Throws: CoreError.unsupported / CoreError.ioError / CoreError.decodeError
    func write(url: URL, tags: TagBundle) throws
}
