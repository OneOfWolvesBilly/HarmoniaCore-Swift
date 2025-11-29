//
//  PlaybackServiceTests.swift
//  HarmoniaCore / Tests
//
//  SPDX-License-Identifier: MIT
//
//  Unit tests for PlaybackService implementation.
//

import XCTest
@testable import HarmoniaCore

final class PlaybackServiceTests: XCTestCase {
    
    var service: DefaultPlaybackService!
    var mockDecoder: MockDecoderPort!
    var mockAudio: MockAudioOutputPort!
    var mockClock: MockClockPort!
    var mockLogger: MockLoggerPort!
    
    override func setUp() {
        super.setUp()
        
        mockDecoder = MockDecoderPort()
        mockAudio = MockAudioOutputPort()
        mockClock = MockClockPort()
        mockLogger = MockLoggerPort()
        
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
        XCTAssertEqual(mockDecoder.lastOpenedURL, testURL)
        XCTAssertTrue(mockDecoder.infoCalled)
        XCTAssertTrue(mockAudio.configureCalled)
        XCTAssertEqual(mockAudio.lastSampleRate, 44100.0)
        XCTAssertEqual(mockAudio.lastChannels, 2)
        XCTAssertEqual(service.duration(), 180.0)
    }
    
    func testLoadFileNotFound() {
        mockDecoder.shouldThrowOnOpen = true
        
        let testURL = URL(fileURLWithPath: "/test/missing.mp3")
        
        XCTAssertThrowsError(try service.load(url: testURL)) { error in
            guard case CoreError.notFound = error else {
                XCTFail("Expected .notFound error")
                return
            }
        }
        
        XCTAssertEqual(service.state, .error(CoreError.notFound("Mock: File not found")))
    }
    
    func testLoadReplacesExistingTrack() throws {
        let url1 = URL(fileURLWithPath: "/test/track1.mp3")
        let url2 = URL(fileURLWithPath: "/test/track2.mp3")
        
        try service.load(url: url1)
        XCTAssertTrue(mockDecoder.openCalled)
        
        mockDecoder.reset()
        
        try service.load(url: url2)
        XCTAssertTrue(mockDecoder.openCalled)
        XCTAssertEqual(mockDecoder.lastOpenedURL, url2)
        XCTAssertTrue(mockDecoder.closeCalled, "Previous track should be closed")
    }
    
    // MARK: - Play Tests
    
    func testPlayWithoutLoad() {
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
    
    func testPlayIsIdempotent() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        mockAudio.reset()
        
        try service.play()
        
        // Should not call start again
        XCTAssertFalse(mockAudio.startCalled)
        XCTAssertEqual(service.state, .playing)
    }
    
    // MARK: - Pause Tests
    
    func testPauseWhilePlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        service.pause()
        
        XCTAssertEqual(service.state, .paused)
        XCTAssertTrue(mockAudio.stopCalled)
    }
    
    func testPauseIsIdempotent() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        service.pause()
        
        XCTAssertEqual(service.state, .paused)
        
        mockAudio.reset()
        service.pause()
        
        // Should not call stop again
        XCTAssertFalse(mockAudio.stopCalled)
    }
    
    // MARK: - Stop Tests
    
    func testStopWhilePlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        service.stop()
        
        XCTAssertEqual(service.state, .stopped)
        XCTAssertTrue(mockAudio.stopCalled)
        XCTAssertTrue(mockDecoder.closeCalled)
        XCTAssertEqual(service.currentTime(), 0.0)
        XCTAssertEqual(service.duration(), 0.0)
    }
    
    func testStopIsIdempotent() {
        service.stop()
        
        XCTAssertEqual(service.state, .stopped)
        
        mockAudio.reset()
        mockDecoder.reset()
        
        service.stop()
        
        XCTAssertFalse(mockAudio.stopCalled)
        XCTAssertFalse(mockDecoder.closeCalled)
    }
    
    // MARK: - Seek Tests
    
    func testSeekSuccess() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        try service.seek(to: 30.0)
        
        XCTAssertTrue(mockDecoder.seekCalled)
        XCTAssertEqual(mockDecoder.lastSeekPosition, 30.0)
    }
    
    func testSeekWithoutLoad() {
        XCTAssertThrowsError(try service.seek(to: 10.0)) { error in
            guard case CoreError.invalidState = error else {
                XCTFail("Expected .invalidState error")
                return
            }
        }
    }
    
    func testSeekNegativePosition() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertThrowsError(try service.seek(to: -5.0)) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testSeekBeyondDuration() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        let duration = service.duration()
        
        XCTAssertThrowsError(try service.seek(to: duration + 10.0)) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    // MARK: - Current Time Tests
    
    func testCurrentTimeWhileStopped() {
        XCTAssertEqual(service.currentTime(), 0.0)
    }
    
    func testCurrentTimeWhilePaused() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.seek(to: 30.0)
        
        XCTAssertEqual(service.currentTime(), 30.0)
    }
    
    func testCurrentTimeWhilePlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        // Advance clock by 5 seconds
        mockClock.advanceSeconds(5.0)
        
        let currentTime = service.currentTime()
        XCTAssertEqual(currentTime, 5.0, accuracy: 0.1)
    }
    
    func testCurrentTimeAfterSeekWhilePlaying() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        mockClock.advanceSeconds(10.0)
        
        try service.seek(to: 30.0)
        
        // Time should reset to seek position
        XCTAssertEqual(service.currentTime(), 30.0, accuracy: 0.1)
        
        mockClock.advanceSeconds(5.0)
        
        XCTAssertEqual(service.currentTime(), 35.0, accuracy: 0.1)
    }
    
    // MARK: - Duration Tests
    
    func testDurationWithoutLoad() {
        XCTAssertEqual(service.duration(), 0.0)
    }
    
    func testDurationAfterLoad() throws {
        mockDecoder.mockStreamInfo = StreamInfo(
            duration: 240.5,
            sampleRate: 48000.0,
            channels: 2,
            bitDepth: 24
        )
        
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        XCTAssertEqual(service.duration(), 240.5)
    }
    
    // MARK: - State Transition Tests
    
    func testStateTransitions() throws {
        // stopped -> paused (via load)
        XCTAssertEqual(service.state, .stopped)
        
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        XCTAssertEqual(service.state, .paused)
        
        // paused -> playing
        try service.play()
        XCTAssertEqual(service.state, .playing)
        
        // playing -> paused
        service.pause()
        XCTAssertEqual(service.state, .paused)
        
        // paused -> playing
        try service.play()
        XCTAssertEqual(service.state, .playing)
        
        // playing -> stopped
        service.stop()
        XCTAssertEqual(service.state, .stopped)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorOnLoad() {
        mockDecoder.shouldThrowOnOpen = true
        
        XCTAssertThrowsError(try service.load(url: URL(fileURLWithPath: "/test/audio.mp3")))
        
        if case .error = service.state {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
    }
    
    func testErrorOnPlay() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        mockAudio.shouldThrowOnStart = true
        
        XCTAssertThrowsError(try service.play())
        
        if case .error = service.state {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompletePlaybackFlow() throws {
        // Simulate short audio file (2 seconds)
        mockDecoder.totalFramesToSimulate = 44100 * 2
        
        try service.load(url: URL(fileURLWithPath: "/test/short.mp3"))
        XCTAssertEqual(service.state, .paused)
        
        try service.play()
        XCTAssertEqual(service.state, .playing)
        
        // Wait a bit for playback loop (this is simplified for unit test)
        Thread.sleep(forTimeInterval: 0.1)
        
        service.pause()
        XCTAssertEqual(service.state, .paused)
        
        try service.seek(to: 0.0)
        
        service.stop()
        XCTAssertEqual(service.state, .stopped)
    }
    
    // MARK: - Logging Tests
    
    func testLogsLoadSuccess() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        
        let loadMessages = mockLogger.messagesContaining("Loading")
        XCTAssertFalse(loadMessages.isEmpty)
        
        let successMessages = mockLogger.messagesContaining("Loaded")
        XCTAssertFalse(successMessages.isEmpty)
    }
    
    func testLogsPlayback() throws {
        try service.load(url: URL(fileURLWithPath: "/test/audio.mp3"))
        try service.play()
        
        let playMessages = mockLogger.messagesContaining("Playing")
        XCTAssertFalse(playMessages.isEmpty)
    }
}

// MARK: - Model Tests

final class StreamInfoTests: XCTestCase {
    
    func testValidStreamInfo() throws {
        let info = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        
        XCTAssertNoThrow(try info.validate())
    }
    
    func testInvalidDuration() {
        let info = StreamInfo(duration: -10.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testInvalidSampleRate() {
        let info = StreamInfo(duration: 180.0, sampleRate: 0, channels: 2, bitDepth: 16)
        
        XCTAssertThrowsError(try info.validate())
    }
    
    func testInvalidChannels() {
        let info = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 0, bitDepth: 16)
        
        XCTAssertThrowsError(try info.validate())
    }
    
    func testInvalidBitDepth() {
        let info = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 4)
        
        XCTAssertThrowsError(try info.validate())
    }
}

final class TagBundleTests: XCTestCase {
    
    func testEmptyTagBundle() {
        let bundle = TagBundle()
        
        XCTAssertTrue(bundle.isEmpty)
        XCTAssertNil(bundle.title)
        XCTAssertNil(bundle.artist)
        XCTAssertNil(bundle.album)
    }
    
    func testNonEmptyTagBundle() {
        let bundle = TagBundle(title: "Test Song", artist: "Test Artist")
        
        XCTAssertFalse(bundle.isEmpty)
        XCTAssertEqual(bundle.title, "Test Song")
        XCTAssertEqual(bundle.artist, "Test Artist")
    }
    
    func testTagBundleEquality() {
        let bundle1 = TagBundle(title: "Song", artist: "Artist")
        let bundle2 = TagBundle(title: "Song", artist: "Artist")
        
        XCTAssertEqual(bundle1, bundle2)
    }
}

final class CoreErrorTests: XCTestCase {
    
    func testErrorEquality() {
        let error1 = CoreError.notFound("File not found")
        let error2 = CoreError.notFound("File not found")
        
        XCTAssertEqual(error1, error2)
    }
    
    func testErrorDescription() {
        let error = CoreError.invalidArgument("Sample rate must be > 0")
        
        XCTAssertTrue(error.description.contains("Invalid argument"))
        XCTAssertTrue(error.description.contains("Sample rate"))
    }
}
