//
//  MockTagReaderPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of TagReaderPort for testing.
//

import Foundation
@testable import HarmoniaCore

public final class MockTagReaderPort: TagReaderPort {
    
    // MARK: - Tracking Properties
    
    public var readCalled = false
    public var lastReadURL: URL?
    public var readCallCount = 0
    
    // MARK: - Configurable Behavior
    
    public var shouldThrowOnRead: CoreError?
    public var mockTagBundle = TagBundle()
    
    // MARK: - Initialization
    
    public init() {
        // Setup default mock tags
        mockTagBundle.title = "Test Song"
        mockTagBundle.artist = "Test Artist"
        mockTagBundle.album = "Test Album"
        mockTagBundle.year = 2025
        mockTagBundle.trackNumber = 1
    }
    
    // MARK: - TagReaderPort Implementation
    
    public func read(url: URL) throws -> TagBundle {
        readCalled = true
        lastReadURL = url
        readCallCount += 1
        
        if let error = shouldThrowOnRead {
            throw error
        }
        
        return mockTagBundle
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        readCalled = false
        lastReadURL = nil
        readCallCount = 0
    }
}
