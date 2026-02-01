//
//  MockDecoderPort.swift
//  HarmoniaCoreTests / Mocks
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementation of DecoderPort for testing.
//

import Foundation
@testable import HarmoniaCore

public final class MockDecoderPort: DecoderPort {
    
    // MARK: - Tracking Properties
    
    public var openCalled = false
    public var readCalled = false
    public var seekCalled = false
    public var infoCalled = false
    public var closeCalled = false
    
    public var lastOpenedURL: URL?
    public var lastSeekPosition: Double?
    public var readCallCount = 0
    
    // MARK: - Configurable Behavior
    
    public var shouldThrowOnOpen: CoreError?
    public var shouldThrowOnRead: CoreError?
    public var shouldThrowOnSeek: CoreError?
    
    public var mockStreamInfo: StreamInfo
    public var generateSilence = true
    public var framesPerRead = 1024
    
    // MARK: - Internal State
    
    private var currentFrame = 0
    private let totalFrames: Int
    
    // MARK: - Initialization
    
    public init(duration: Double = 10.0, sampleRate: Double = 44100.0, channels: Int = 2) {
        self.totalFrames = Int(duration * sampleRate)
        self.mockStreamInfo = StreamInfo(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            bitDepth: 16
        )
    }
    
    // MARK: - DecoderPort Implementation
    
    public func open(url: URL) throws -> DecodeHandle {
        openCalled = true
        lastOpenedURL = url
        
        if let error = shouldThrowOnOpen {
            throw error
        }
        
        currentFrame = 0
        return DecodeHandle(id: UUID())
    }
    
    public func read(
        _ handle: DecodeHandle,
        into pcmInterleaved: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) throws -> Int {
        readCalled = true
        readCallCount += 1
        
        if let error = shouldThrowOnRead {
            throw error
        }
        
        // Check EOF
        let remainingFrames = totalFrames - currentFrame
        if remainingFrames <= 0 {
            return 0
        }
        
        // Calculate frames to return
        let framesToReturn = min(maxFrames, min(framesPerRead, remainingFrames))
        
        // Generate mock audio data
        if generateSilence {
            // Fill with silence
            for i in 0..<(framesToReturn * mockStreamInfo.channels) {
                pcmInterleaved[i] = 0.0
            }
        } else {
            // Generate 440Hz sine wave for testing
            let frequency = 440.0
            let sampleRate = mockStreamInfo.sampleRate
            
            for frame in 0..<framesToReturn {
                let t = Double(currentFrame + frame) / sampleRate
                let sample = Float(sin(2.0 * .pi * frequency * t))
                
                // Interleaved stereo
                for channel in 0..<mockStreamInfo.channels {
                    pcmInterleaved[frame * mockStreamInfo.channels + channel] = sample
                }
            }
        }
        
        currentFrame += framesToReturn
        return framesToReturn
    }
    
    public func seek(_ handle: DecodeHandle, toSeconds: Double) throws {
        seekCalled = true
        lastSeekPosition = toSeconds
        
        if let error = shouldThrowOnSeek {
            throw error
        }
        
        currentFrame = Int(toSeconds * mockStreamInfo.sampleRate)
    }
    
    public func info(_ handle: DecodeHandle) throws -> StreamInfo {
        infoCalled = true
        return mockStreamInfo
    }
    
    public func close(_ handle: DecodeHandle) {
        closeCalled = true
        currentFrame = 0
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        openCalled = false
        readCalled = false
        seekCalled = false
        infoCalled = false
        closeCalled = false
        lastOpenedURL = nil
        lastSeekPosition = nil
        readCallCount = 0
        currentFrame = 0
    }
}
