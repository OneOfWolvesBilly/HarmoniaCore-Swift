//
//  DefaultPlaybackServiceTests.swift
//  HarmoniaCoreTests / Services
//
//  SPDX-License-Identifier: MIT
//
//  Comprehensive tests for DefaultPlaybackService.
//

import XCTest
@testable import HarmoniaCore

final class DefaultPlaybackServiceTests: XCTestCase {
    
    var service: DefaultPlaybackService!
    var mockDecoder: MockDecoderPort!
    var mockAudio: MockAudioOutputPort!
    var mockClock: MockClockPort!
    var mockLogger: NoopLogger!
    
    override func setUp() {
        super.setUp()
        
        mockDecoder = MockDecoderPort(duration: 10.0, sampleRate: 44100.0)
        mockAudio = MockAudioOutputPort()
        mockClock = MockClockPort()
        mockLogger = NoopLogger()
        
        service = DefaultPlaybackService(
            decoder: mockDecoder,
            audio: mockAudio,
            clock: mockClock,
            logger: mockLogger
        )
    }
    
    override func tearDown() {
        service = nil
        mockDecoder = nil
        mockAudio = nil
        mockClock = nil
        mockLogger = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.currentTime(), 0.0)
        XCTAssertEqual(service.duration(), 0.0)
    }
    
    // MARK: - Load Tests
    
    func testLoadSuccess() throws {
        let testURL = URL(fileURLWithPath: "/test/audio.mp3")
        
        try service.load(url: testURL)
        
        XCTAssertEqual(service.state, .paused)
        XCTAssertTrue(mockDecoder.openCalled)
        XCTAssertTrue(mockDecoder.infoCalled)
        XCTAssertEqual(mockDecoder.lastOpenedURL, testURL)
        XCTAssertTrue(mockAudio.configureCalled)
        XCTAssertEqual(service.duration(), 10.0)
    }
    
    func testLoadFailure_FileNotFound() {
        mockDecoder.shouldThrowOnOpen = .notFound("File not found")
        
        XCTAssertThrowsError(try service.load(url: URL(fileURLWithPath: "/test/missing.mp3"))) { error in
            guard case CoreError.notFound = error else {
                XCTFail("Expected .notFound error")
                return
            }
        }
        
        XCTAssertEqual(service.state, .error(CoreError.notFound("File not found")))
    }
    
    // MARK: - Play Tests
    
    func testPlayWithoutLoad_ThrowsInvalidState() {
        XCTAssertThrowsError(try service.play()) { error in
            guard case CoreError.invalidState = error else {
                XCTFail("Expected .invalidState error")
                return
            }
        }
    }
    
    func testPlaySuccess() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        try service.play()
        
        XCTAssertEqual(service.state, .playing)
        XCTAssertTrue(mockAudio.startCalled)
    }
    
    func testPlayIdempotent() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        mockAudio.reset()
        try service.play() // Call again
        
        XCTAssertEqual(service.state, .playing)
        XCTAssertFalse(mockAudio.startCalled, "start() should not be called again")
    }
    
    // MARK: - Pause Tests
    
    func testPauseFromPlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        service.pause()
        
        XCTAssertEqual(service.state, .paused)
        XCTAssertTrue(mockAudio.stopCalled)
    }
    
    func testPauseIdempotent() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        service.pause()
        mockAudio.reset()
        service.pause() // Call again
        
        XCTAssertEqual(service.state, .paused)
        XCTAssertFalse(mockAudio.stopCalled, "stop() should not be called again")
    }
    
    // MARK: - Stop Tests
    
    func testStop() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        service.stop()
        
        XCTAssertEqual(service.state, .stopped)
        XCTAssertTrue(mockAudio.stopCalled)
        XCTAssertTrue(mockDecoder.closeCalled)
        XCTAssertEqual(service.duration(), 0.0)
    }
    
    func testStopIdempotent() {
        service.stop()
        mockAudio.reset()
        mockDecoder.reset()
        service.stop() // Call again
        
        XCTAssertEqual(service.state, .stopped)
        XCTAssertFalse(mockAudio.stopCalled)
        XCTAssertFalse(mockDecoder.closeCalled)
    }
    
    // MARK: - Seek Tests
    
    func testSeekSuccess() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        try service.seek(to: 5.0)
        
        XCTAssertTrue(mockDecoder.seekCalled)
        XCTAssertEqual(mockDecoder.lastSeekPosition, 5.0)
    }
    
    func testSeekNegativePosition_ThrowsInvalidArgument() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertThrowsError(try service.seek(to: -1.0)) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testSeekBeyondDuration_ThrowsInvalidArgument() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertThrowsError(try service.seek(to: 100.0)) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testSeekWithoutLoad_ThrowsInvalidState() {
        XCTAssertThrowsError(try service.seek(to: 5.0)) { error in
            guard case CoreError.invalidState = error else {
                XCTFail("Expected .invalidState error")
                return
            }
        }
    }
    
    // MARK: - Position Tracking Tests
    
    func testCurrentTimeWhenStopped() {
        XCTAssertEqual(service.currentTime(), 0.0)
    }
    
    func testCurrentTimeWhenPaused() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        XCTAssertEqual(service.currentTime(), 0.0)
    }
    
    func testCurrentTimeWhenPlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        // Advance clock by 2 seconds
        mockClock.advanceSeconds(2.0)
        
        let currentTime = service.currentTime()
        XCTAssertEqual(currentTime, 2.0, accuracy: 0.1)
    }
    
    func testCurrentTimeAfterSeek() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.seek(to: 5.0)
        
        let currentTime = service.currentTime()
        XCTAssertEqual(currentTime, 5.0, accuracy: 0.1)
    }
    
    // MARK: - Error Recovery Tests
    
    func testLoadAfterError() throws {
        // First load fails
        mockDecoder.shouldThrowOnOpen = .notFound("File not found")
        XCTAssertThrowsError(try service.load(url: URL(fileURLWithPath: "/test/missing.mp3")))
        XCTAssertEqual(service.state, .error(CoreError.notFound("File not found")))
        
        // Reset mock and try again
        mockDecoder.reset()
        mockDecoder.shouldThrowOnOpen = nil
        
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertEqual(service.state, .paused)
    }
    
    // MARK: - State Transition Tests
    
    func testStateTransition_StoppedToPaused() throws {
        XCTAssertEqual(service.state, .stopped)
        
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertEqual(service.state, .paused)
    }
    
    func testStateTransition_PausedToPlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        XCTAssertEqual(service.state, .paused)
        
        try service.play()
        
        XCTAssertEqual(service.state, .playing)
    }
    
    func testStateTransition_PlayingToPaused() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        XCTAssertEqual(service.state, .playing)
        
        service.pause()
        
        XCTAssertEqual(service.state, .paused)
    }
    
    func testStateTransition_PlayingToStopped() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        XCTAssertEqual(service.state, .playing)
        
        service.stop()
        
        XCTAssertEqual(service.state, .stopped)
    }
}
