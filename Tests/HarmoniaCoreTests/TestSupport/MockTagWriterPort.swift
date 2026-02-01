//
//  MockTagWriterPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of TagWriterPort for testing.
//

import Foundation
@testable import HarmoniaCore

public final class MockTagWriterPort: TagWriterPort {
    
    // MARK: - Tracking Properties
    
    public var writeCalled = false
    public var lastWriteURL: URL?
    public var lastWrittenTags: TagBundle?
    public var writeCallCount = 0
    
    // MARK: - Configurable Behavior
    
    public var shouldThrowOnWrite: CoreError?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - TagWriterPort Implementation
    
    public func write(url: URL, tags: TagBundle) throws {
        writeCalled = true
        lastWriteURL = url
        lastWrittenTags = tags
        writeCallCount += 1
        
        if let error = shouldThrowOnWrite {
            throw error
        }
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        writeCalled = false
        lastWriteURL = nil
        lastWrittenTags = nil
        writeCallCount = 0
    }
}
