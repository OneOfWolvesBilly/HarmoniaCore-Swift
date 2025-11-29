//
//  SandboxFileAccessAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements FileAccessPort using FileHandle with sandbox-safe access.
//
import Foundation

public final class SandboxFileAccessAdapter: FileAccessPort {

    private let lock = NSLock()
    private var handles: [UUID: FileHandle] = [:]

    public init() {}

    public func open(url: URL) throws -> FileHandleToken {
            lock.lock()
            defer { lock.unlock() }

            guard url.isFileURL else {
                throw CoreError.invalidArgument("SandboxFileAccessAdapter supports only file URLs")
            }

            do {
                let fileHandle = try FileHandle(forReadingFrom: url)
                let token = FileHandleToken(id: UUID())
                handles[token.id] = fileHandle
                return token
            } catch {
                throw CoreError.ioError(underlying: error)
            }
        }

    public func read(_ token: FileHandleToken,
                         into buffer: UnsafeMutableRawPointer,
                         count: Int) throws -> Int {
        lock.lock()

        guard let fileHandle = handles[token.id] else {
            lock.unlock()
            throw CoreError.invalidState("Unknown FileHandleToken")
        }

        let data: Data
        do {
            data = try fileHandle.read(upToCount: count) ?? Data()
        } catch {
            lock.unlock()
            throw CoreError.ioError(underlying: error)
        }

        let bytesRead = data.count
        if bytesRead > 0 {
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
        }

        lock.unlock()
        return bytesRead
    }

    public func seek(_ token: FileHandleToken,
                     offset: Int64,
                     origin: FileSeekOrigin) throws {
        lock.lock()

        guard let fileHandle = handles[token.id] else {
            lock.unlock()
            throw CoreError.invalidState("Unknown FileHandleToken")
        }

        let currentOffset = fileHandle.offsetInFile
        let fileSize: UInt64

        do {
            fileSize = try fileHandle.seekToEnd()
            try fileHandle.seek(toOffset: currentOffset)
        } catch {
            lock.unlock()
            throw CoreError.ioError(underlying: error)
        }

        let baseOffset: Int64
        switch origin {
        case .start:
            baseOffset = 0
        case .current:
            baseOffset = Int64(currentOffset)
        case .end:
            baseOffset = Int64(fileSize)
        }

        var targetOffset = baseOffset + offset
        if targetOffset < 0 {
            targetOffset = 0
        } else if targetOffset > Int64(fileSize) {
            targetOffset = Int64(fileSize)
        }

        do {
            try fileHandle.seek(toOffset: UInt64(targetOffset))
        } catch {
            lock.unlock()
            throw CoreError.ioError(underlying: error)
        }

        lock.unlock()
    }

    public func size(_ token: FileHandleToken) throws -> Int64 {
        lock.lock()

        guard let fileHandle = handles[token.id] else {
            lock.unlock()
            throw CoreError.invalidState("Unknown FileHandleToken")
        }

        let currentOffset = fileHandle.offsetInFile
        let endOffset: UInt64

        do {
            endOffset = try fileHandle.seekToEnd()
            try fileHandle.seek(toOffset: currentOffset)
        } catch {
            lock.unlock()
            throw CoreError.ioError(underlying: error)
        }

        lock.unlock()
        return Int64(endOffset)
    }

    public func close(_ token: FileHandleToken) {
        lock.lock()
        if let fileHandle = handles.removeValue(forKey: token.id) {
            try? fileHandle.close()
        }
        lock.unlock()
    }
}
