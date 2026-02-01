//
//  MockClockPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of ClockPort for testing time-dependent behavior.
//

import Foundation
@testable import HarmoniaCore

public final class MockClockPort: ClockPort {
    
    private var currentTime: UInt64
    public var nowCallCount = 0
    
    public init(startTime: UInt64 = 0) {
        self.currentTime = startTime
    }
    
    public func now() -> UInt64 {
        nowCallCount += 1
        return currentTime
    }
    
    // MARK: - Test Helpers
    
    /// Advance time by nanoseconds
    public func advance(by nanoseconds: UInt64) {
        currentTime += nanoseconds
    }
    
    /// Advance time by seconds
    public func advanceSeconds(_ seconds: Double) {
        currentTime += UInt64(seconds * 1_000_000_000)
    }
    
    /// Reset clock to specific time
    public func reset(to time: UInt64 = 0) {
        currentTime = time
        nowCallCount = 0
    }
}
