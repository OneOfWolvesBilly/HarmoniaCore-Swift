//
//  MockEQPort.swift
//  HarmoniaCoreTests / TestSupport
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of EQPort for testing.
//

@testable import HarmoniaCore

public final class MockEQPort: EQPort {

    // MARK: - EQPort state

    public var isEnabled: Bool = false
    public var preamp: Float = 0
    public var bandGains: [Float] = Array(repeating: 0, count: 10)

    // MARK: - Init

    public init() {}
}
