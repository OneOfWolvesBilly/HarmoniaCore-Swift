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
    
    // MARK: - Tracking Properties
    
    public var configureCalled = false
    public var startCalled = false
    public var stopCalled = false
    public var renderCalled = false
    
    public var lastConfiguredSampleRate: Double?
    public var lastConfiguredChannels: Int?
    public var lastConfiguredFramesPerBuffer: Int?
    public var renderCallCount = 0
    public var totalFramesRendered = 0
    
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
    
    public func reset() {
        configureCalled = false
        startCalled = false
        stopCalled = false
        renderCalled = false
        renderCallCount = 0
        totalFramesRendered = 0
        renderedAudioData.removeAll()
        lastConfiguredSampleRate = nil
        lastConfiguredChannels = nil
        lastConfiguredFramesPerBuffer = nil
    }
}
