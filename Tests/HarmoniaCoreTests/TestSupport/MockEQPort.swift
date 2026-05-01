//
//  MockEQPort.swift
//  HarmoniaCoreTests / TestSupport
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of EQPort for testing.
//

import AVFoundation
@testable import HarmoniaCore

public final class MockEQPort: EQPort {

    // MARK: - EQPort state

    public var isEnabled: Bool = false
    public var preamp: Float = 0
    public var bandGains: [Float] = Array(repeating: 0, count: 10)

    // MARK: - Tracking properties

    public var attachCalled = false
    public var attachCallCount = 0
    public var lastAttachEngine: AVAudioEngine?
    public var lastAttachPrevious: AVAudioNode?

    // MARK: - Configurable behaviour

    /// If non-nil, `attach(to:after:)` throws this error.
    public var shouldThrowOnAttach: Error?

    // MARK: - Init

    public init() {}

    // MARK: - EQPort

    public func attach(to engine: AVAudioEngine, after previous: AVAudioNode) throws {
        attachCalled = true
        attachCallCount += 1
        lastAttachEngine = engine
        lastAttachPrevious = previous
        if let error = shouldThrowOnAttach {
            throw error
        }
    }
}
