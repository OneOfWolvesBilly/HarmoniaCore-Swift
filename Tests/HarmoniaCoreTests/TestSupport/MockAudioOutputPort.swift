//
//  MockAudioOutputPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of AudioOutputPort for testing.
//

import Foundation
@testable import HarmoniaCore

public final class MockAudioOutputPort: AudioOutputPort {

    /// Invalidation callback (AudioOutputPort). The owner under test installs
    /// its handler here at construction time; fire it with `simulateInvalidation()`.
    public var onInvalidated: (() -> Void)?

    // MARK: - Tracking Properties
    
    public var configureCalled = false
    public var configureCallCount = 0
    public var startCalled = false
    public var stopCalled = false
    public var renderCalled = false
    
    public var lastConfiguredSampleRate: Double?
    public var lastConfiguredChannels: Int?
    public var lastConfiguredFramesPerBuffer: Int?
    public var renderCallCount = 0
    public var totalFramesRendered = 0

    /// Number of times `setVolume(_:)` was called.
    public var setVolumeCallCount = 0

    /// Last volume value passed to `setVolume(_:)`. Defaults to 1.0 (no call yet).
    public var lastSetVolume: Float = 1.0
    
    // MARK: - Captured Data
    
    public var renderedAudioData: [[Float]] = []
    
    // MARK: - Configurable Behavior
    
    public var shouldThrowOnConfigure: CoreError?
    public var shouldThrowOnStart: CoreError?
    public var shouldThrowOnRender: CoreError?
    public var maxFramesPerRender = Int.max
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - AudioOutputPort Implementation
    
    public func configure(sampleRate: Double, channels: Int, framesPerBuffer: Int) throws {
        configureCalled = true
        configureCallCount += 1
        lastConfiguredSampleRate = sampleRate
        lastConfiguredChannels = channels
        lastConfiguredFramesPerBuffer = framesPerBuffer
        
        if let error = shouldThrowOnConfigure {
            throw error
        }
    }
    
    public func start() throws {
        startCalled = true
        
        if let error = shouldThrowOnStart {
            throw error
        }
    }
    
    public func stop() {
        stopCalled = true
    }

    public func flush() {
        // No-op in mock
    }

    public func setVolume(_ volume: Float) {
        setVolumeCallCount += 1
        lastSetVolume = volume
    }
    
    public func render(_ interleavedFloat32: UnsafePointer<Float>, frameCount: Int) throws -> Int {
        renderCalled = true
        renderCallCount += 1
        
        if let error = shouldThrowOnRender {
            throw error
        }
        
        let framesToConsume = min(frameCount, maxFramesPerRender)
        
        // Capture audio data for verification
        let channels = lastConfiguredChannels ?? 2
        var capturedData = [Float]()
        for i in 0..<(framesToConsume * channels) {
            capturedData.append(interleavedFloat32[i])
        }
        renderedAudioData.append(capturedData)
        
        totalFramesRendered += framesToConsume
        return framesToConsume
    }
    
    // MARK: - Test Helpers

    /// Fires the invalidation callback, mimicking an adapter that has already
    /// stopped itself, discarded its configuration, and released render() waiters.
    public func simulateInvalidation() {
        onInvalidated?()
    }

    public func reset() {
        configureCalled = false
        configureCallCount = 0
        startCalled = false
        stopCalled = false
        renderCalled = false
        renderCallCount = 0
        totalFramesRendered = 0
        renderedAudioData.removeAll()
        lastConfiguredSampleRate = nil
        lastConfiguredChannels = nil
        lastConfiguredFramesPerBuffer = nil
        setVolumeCallCount = 0
        lastSetVolume = 1.0
    }
}
