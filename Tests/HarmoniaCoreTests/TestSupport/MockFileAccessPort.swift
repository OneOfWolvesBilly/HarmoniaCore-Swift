//
//  MockFileAccessPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of FileAccessPort for testing.
//

import Foundation
@testable import HarmoniaCore

public final class MockFileAccessPort: FileAccessPort {
    
    // MARK: - Tracking Properties
    
    public var openCalled = false
    public var readCalled = false
    public var seekCalled = false
    public var sizeCalled = false
    public var closeCalled = false
    
    public var lastOpenedURL: URL?
    public var lastSeekOffset: Int64?
    public var lastSeekOrigin: FileSeekOrigin?
    public var readCallCount = 0
    
    // MARK: - Configurable Behavior
    
    public var shouldThrowOnOpen: CoreError?
    public var shouldThrowOnRead: CoreError?
    public var shouldThrowOnSeek: CoreError?
    public var shouldThrowOnSize: CoreError?
    
    public var mockFileSize: Int64 = 1024 * 1024 // 1MB
    public var mockFileContent: Data = Data()
    
    // MARK: - Internal State
    
    private var currentPosition: Int64 = 0
    private var openHandles: [UUID: Int64] = [:] // token -> position
    
    // MARK: - Initialization
    
    public init() {
        // Generate some mock file content
        mockFileContent = Data(repeating: 0x42, count: Int(mockFileSize))
    }
    
    // MARK: - FileAccessPort Implementation
    
    public func open(url: URL) throws -> FileHandleToken {
        openCalled = true
        lastOpenedURL = url
        
        if let error = shouldThrowOnOpen {
            throw error
        }
        
        let token = FileHandleToken(id: UUID())
        openHandles[token.id] = 0 // Start at position 0
        return token
    }
    
    public func read(
        _ token: FileHandleToken,
        into buffer: UnsafeMutableRawPointer,
        count: Int
    ) throws -> Int {
        readCalled = true
        readCallCount += 1
        
        if let error = shouldThrowOnRead {
            throw error
        }
        
        guard let position = openHandles[token.id] else {
            throw CoreError.invalidState("Unknown FileHandleToken")
        }
        
        // Calculate how many bytes we can read
        let remaining = mockFileSize - position
        let bytesToRead = min(Int64(count), remaining)
        
        if bytesToRead <= 0 {
            return 0 // EOF
        }
        
        // Copy data to buffer
        let startIndex = Int(position)
        let endIndex = startIndex + Int(bytesToRead)
        mockFileContent.withUnsafeBytes { sourceBytes in
            let sourcePtr = sourceBytes.baseAddress!
            let typedPtr = sourcePtr.assumingMemoryBound(to: UInt8.self)
            buffer.copyMemory(from: typedPtr.advanced(by: startIndex), byteCount: Int(bytesToRead))
        }
        
        // Update position
        openHandles[token.id] = position + bytesToRead
        
        return Int(bytesToRead)
    }
    
    public func seek(
        _ token: FileHandleToken,
        offset: Int64,
        origin: FileSeekOrigin
    ) throws {
        seekCalled = true
        lastSeekOffset = offset
        lastSeekOrigin = origin
        
        if let error = shouldThrowOnSeek {
            throw error
        }
        
        guard let currentPosition = openHandles[token.id] else {
            throw CoreError.invalidState("Unknown FileHandleToken")
        }
        
        let newPosition: Int64
        switch origin {
        case .start:
            newPosition = offset
        case .current:
            newPosition = currentPosition + offset
        case .end:
            newPosition = mockFileSize + offset
        }
        
        // Validate position
        guard newPosition >= 0 && newPosition <= mockFileSize else {
            throw CoreError.invalidArgument("Seek position out of bounds")
        }
        
        openHandles[token.id] = newPosition
    }
    
    public func size(_ token: FileHandleToken) throws -> Int64 {
        sizeCalled = true
        
        if let error = shouldThrowOnSize {
            throw error
        }
        
        guard openHandles[token.id] != nil else {
            throw CoreError.invalidState("Unknown FileHandleToken")
        }
        
        return mockFileSize
    }
    
    public func close(_ token: FileHandleToken) {
        closeCalled = true
        openHandles.removeValue(forKey: token.id)
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        openCalled = false
        readCalled = false
        seekCalled = false
        sizeCalled = false
        closeCalled = false
        lastOpenedURL = nil
        lastSeekOffset = nil
        lastSeekOrigin = nil
        readCallCount = 0
        currentPosition = 0
        openHandles.removeAll()
    }
    
    public func setFileContent(_ data: Data) {
        mockFileContent = data
        mockFileSize = Int64(data.count)
    }
}
