//
//  MockPorts.swift
//  HarmoniaCore / Tests
//
//  SPDX-License-Identifier: MIT
//
//  Mock implementations of all Ports for unit testing.
//

import Foundation

// MARK: - MockDecoderPort

public final class MockDecoderPort: DecoderPort {
    // Configuration
    public var shouldThrowOnOpen = false
    public var shouldThrowOnRead = false
    public var shouldThrowOnSeek = false
    public var mockStreamInfo = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
    public var mockFramesPerRead = 1024
    public var totalFramesToSimulate = 44100 * 10 // 10 seconds at 44.1kHz
    
    // State tracking
    public var openCalled = false
    public var lastOpenedURL: URL?
    public var readCount = 0
    public var seekCalled = false
    public var lastSeekPosition: Double = 0
    public var infoCalled = false
    public var closeCalled = false
    
    private var currentHandle: DecodeHandle?
    private var framesRead = 0
    
    public init() {}
    
    public func open(url: URL) throws -> DecodeHandle {
        openCalled = true
        lastOpenedURL = url
        
        if shouldThrowOnOpen {
            throw CoreError.notFound("Mock: File not found")
        }
        
        let handle = DecodeHandle(id: UUID())
        currentHandle = handle
        framesRead = 0
        
        return handle
    }
    
    public func read(
        _ handle: DecodeHandle,
        into pcmInterleaved: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) throws -> Int {
        readCount += 1
        
        if shouldThrowOnRead {
            throw CoreError.decodeError("Mock: Decode failed")
        }
        
        guard handle == currentHandle else {
            throw CoreError.invalidState("Mock: Invalid handle")
        }
        
        // Simulate reading frames
        let framesToReturn = min(maxFrames, mockFramesPerRead, totalFramesToSimulate - framesRead)
        
        if framesToReturn > 0 {
            // Fill with mock data (sine wave)
            let channels = mockStreamInfo.channels
            for frame in 0..<framesToReturn {
                let sampleValue = sin(Double(framesRead + frame) * 0.01)
                for ch in 0..<channels {
                    pcmInterleaved[frame * channels + ch] = Float(sampleValue)
                }
            }
            
            framesRead += framesToReturn
        }
        
        return framesToReturn
    }
    
    public func seek(_ handle: DecodeHandle, toSeconds: Double) throws {
        seekCalled = true
        lastSeekPosition = toSeconds
        
        if shouldThrowOnSeek {
            throw CoreError.unsupported("Mock: Seek not supported")
        }
        
        guard handle == currentHandle else {
            throw CoreError.invalidState("Mock: Invalid handle")
        }
        
        // Simulate seek
        let sampleRate = mockStreamInfo.sampleRate
        framesRead = Int(toSeconds * sampleRate)
    }
    
    public func info(_ handle: DecodeHandle) throws -> StreamInfo {
        infoCalled = true
        
        guard handle == currentHandle else {
            throw CoreError.invalidState("Mock: Invalid handle")
        }
        
        return mockStreamInfo
    }
    
    public func close(_ handle: DecodeHandle) {
        closeCalled = true
        if handle == currentHandle {
            currentHandle = nil
            framesRead = 0
        }
    }
    
    // Helper for tests
    public func reset() {
        openCalled = false
        lastOpenedURL = nil
        readCount = 0
        seekCalled = false
        lastSeekPosition = 0
        infoCalled = false
        closeCalled = false
        currentHandle = nil
        framesRead = 0
    }
}

// MARK: - MockAudioOutputPort

public final class MockAudioOutputPort: AudioOutputPort {
    // Configuration
    public var shouldThrowOnConfigure = false
    public var shouldThrowOnStart = false
    
    // State tracking
    public var configureCalled = false
    public var lastSampleRate: Double = 0
    public var lastChannels: Int = 0
    public var lastFramesPerBuffer: Int = 0
    public var startCalled = false
    public var stopCalled = false
    public var renderCalled = false
    public var totalFramesRendered = 0
    
    public init() {}
    
    public func configure(sampleRate: Double, channels: Int, framesPerBuffer: Int) throws {
        configureCalled = true
        lastSampleRate = sampleRate
        lastChannels = channels
        lastFramesPerBuffer = framesPerBuffer
        
        if shouldThrowOnConfigure {
            throw CoreError.invalidArgument("Mock: Invalid configuration")
        }
    }
    
    public func start() throws {
        startCalled = true
        
        if shouldThrowOnStart {
            throw CoreError.ioError(underlying: NSError(
                domain: "MockAudioOutput",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Mock start failed"]
            ))
        }
    }
    
    public func stop() {
        stopCalled = true
    }
    
    public func render(_ interleavedFloat32: UnsafePointer<Float>, frameCount: Int) throws -> Int {
        renderCalled = true
        totalFramesRendered += frameCount
        return frameCount
    }
    
    // Helper for tests
    public func reset() {
        configureCalled = false
        lastSampleRate = 0
        lastChannels = 0
        lastFramesPerBuffer = 0
        startCalled = false
        stopCalled = false
        renderCalled = false
        totalFramesRendered = 0
    }
}

// MARK: - MockClockPort

public final class MockClockPort: ClockPort {
    private var currentTime: UInt64 = 0
    private let lock = NSLock()
    
    public init(startTime: UInt64 = 0) {
        self.currentTime = startTime
    }
    
    public func now() -> UInt64 {
        lock.withLock { currentTime }
    }
    
    // Test helpers
    public func advance(by nanoseconds: UInt64) {
        lock.withLock {
            currentTime += nanoseconds
        }
    }
    
    public func advanceSeconds(_ seconds: Double) {
        advance(by: UInt64(seconds * 1_000_000_000))
    }
    
    public func reset(to time: UInt64 = 0) {
        lock.withLock {
            currentTime = time
        }
    }
}

// MARK: - MockLoggerPort

public final class MockLoggerPort: LoggerPort {
    public struct LogEntry {
        public let level: String
        public let message: String
        public let timestamp: Date
    }
    
    public private(set) var entries: [LogEntry] = []
    private let lock = NSLock()
    
    public init() {}
    
    public func debug(_ msg: @autoclosure () -> String) {
        log(level: "DEBUG", message: msg())
    }
    
    public func info(_ msg: @autoclosure () -> String) {
        log(level: "INFO", message: msg())
    }
    
    public func warn(_ msg: @autoclosure () -> String) {
        log(level: "WARN", message: msg())
    }
    
    public func error(_ msg: @autoclosure () -> String) {
        log(level: "ERROR", message: msg())
    }
    
    private func log(level: String, message: String) {
        lock.withLock {
            entries.append(LogEntry(level: level, message: message, timestamp: Date()))
        }
    }
    
    // Test helpers
    public func reset() {
        lock.withLock {
            entries.removeAll()
        }
    }
    
    public func messagesContaining(_ substring: String) -> [LogEntry] {
        lock.withLock {
            entries.filter { $0.message.contains(substring) }
        }
    }
}
