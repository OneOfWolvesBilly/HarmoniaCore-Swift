//
//  TagBundleTests.swift
//  HarmoniaCoreTests / Models
//
//  SPDX-License-Identifier: MIT
//
//  Tests for TagBundle model.
//

import XCTest
@testable import HarmoniaCore

final class TagBundleTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization_Empty() {
        let tags = TagBundle()
        
        XCTAssertNil(tags.title)
        XCTAssertNil(tags.artist)
        XCTAssertNil(tags.album)
        XCTAssertNil(tags.albumArtist)
        XCTAssertNil(tags.composer)
        XCTAssertNil(tags.genre)
        XCTAssertNil(tags.year)
        XCTAssertNil(tags.trackNumber)
        XCTAssertNil(tags.trackTotal)
        XCTAssertNil(tags.discNumber)
        XCTAssertNil(tags.discTotal)
        XCTAssertNil(tags.bpm)
        XCTAssertNil(tags.replayGainTrack)
        XCTAssertNil(tags.replayGainAlbum)
        XCTAssertNil(tags.comment)
        XCTAssertNil(tags.artworkData)
    }
    
    func testInitialization_WithParameters() {
        let tags = TagBundle(
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            year: 2025,
            trackNumber: 5
        )
        
        XCTAssertEqual(tags.title, "Test Song")
        XCTAssertEqual(tags.artist, "Test Artist")
        XCTAssertEqual(tags.album, "Test Album")
        XCTAssertEqual(tags.year, 2025)
        XCTAssertEqual(tags.trackNumber, 5)
    }
    
    // MARK: - isEmpty Tests
    
    func testIsEmpty_WhenEmpty() {
        let tags = TagBundle()
        XCTAssertTrue(tags.isEmpty)
    }
    
    func testIsEmpty_WithTitle() {
        var tags = TagBundle()
        tags.title = "Test Song"
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testIsEmpty_WithArtist() {
        var tags = TagBundle()
        tags.artist = "Test Artist"
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testIsEmpty_WithYear() {
        var tags = TagBundle()
        tags.year = 2025
        XCTAssertFalse(tags.isEmpty)
    }

    func testIsEmpty_WithComposer() {
        var tags = TagBundle()
        tags.composer = "John Williams"
        XCTAssertFalse(tags.isEmpty)
    }

    func testIsEmpty_WithBpm() {
        var tags = TagBundle()
        tags.bpm = 120
        XCTAssertFalse(tags.isEmpty)
    }

    func testIsEmpty_WithComment() {
        var tags = TagBundle()
        tags.comment = "A note"
        XCTAssertFalse(tags.isEmpty)
    }

    func testIsEmpty_WithReplayGainTrack() {
        var tags = TagBundle()
        tags.replayGainTrack = -3.21
        XCTAssertFalse(tags.isEmpty)
    }
    
    // MARK: - Equatable Tests
    
    func testEquatable_EqualTags() {
        let tags1 = TagBundle(title: "Song", artist: "Artist")
        let tags2 = TagBundle(title: "Song", artist: "Artist")
        
        XCTAssertEqual(tags1, tags2)
    }
    
    func testEquatable_DifferentTitle() {
        let tags1 = TagBundle(title: "Song 1", artist: "Artist")
        let tags2 = TagBundle(title: "Song 2", artist: "Artist")
        
        XCTAssertNotEqual(tags1, tags2)
    }
    
    func testEquatable_OneNilField() {
        let tags1 = TagBundle(title: "Song", artist: "Artist")
        let tags2 = TagBundle(title: "Song")
        
        XCTAssertNotEqual(tags1, tags2)
    }
    
    // MARK: - Typical Usage Tests
    
    func testTypicalUsage_MP3Tags() {
        var tags = TagBundle()
        tags.title = "Bohemian Rhapsody"
        tags.artist = "Queen"
        tags.album = "A Night at the Opera"
        tags.albumArtist = "Queen"
        tags.genre = "Rock"
        tags.year = 1975
        tags.trackNumber = 11
        tags.discNumber = 1
        
        XCTAssertFalse(tags.isEmpty)
        XCTAssertEqual(tags.title, "Bohemian Rhapsody")
        XCTAssertEqual(tags.artist, "Queen")
        XCTAssertEqual(tags.year, 1975)
    }
    
    func testTypicalUsage_WithArtwork() {
        var tags = TagBundle()
        tags.title = "Test Song"
        
        let mockArtwork = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        tags.artworkData = mockArtwork
        
        XCTAssertFalse(tags.isEmpty)
        XCTAssertEqual(tags.artworkData, mockArtwork)
    }

    // MARK: - New field tests (composer, trackTotal, discTotal, bpm, replayGain, comment)

    func testComposer_StoresString() {
        var tags = TagBundle()
        tags.composer = "John Williams"
        XCTAssertEqual(tags.composer, "John Williams")
    }

    func testTrackTotal_StoresPositiveInt() {
        var tags = TagBundle()
        tags.trackTotal = 12
        XCTAssertEqual(tags.trackTotal, 12)
    }

    func testDiscTotal_StoresPositiveInt() {
        var tags = TagBundle()
        tags.discTotal = 2
        XCTAssertEqual(tags.discTotal, 2)
    }

    func testBpm_StoresPositiveInt() {
        var tags = TagBundle()
        tags.bpm = 128
        XCTAssertEqual(tags.bpm, 128)
    }

    func testReplayGainTrack_StoresDouble() {
        var tags = TagBundle()
        tags.replayGainTrack = -3.21
        XCTAssertEqual(tags.replayGainTrack ?? 0, -3.21, accuracy: 0.001)
    }

    func testReplayGainAlbum_StoresDouble() {
        var tags = TagBundle()
        tags.replayGainAlbum = 1.50
        XCTAssertEqual(tags.replayGainAlbum ?? 0, 1.50, accuracy: 0.001)
    }

    func testComment_StoresString() {
        var tags = TagBundle()
        tags.comment = "Remastered 2023"
        XCTAssertEqual(tags.comment, "Remastered 2023")
    }

    func testInitialization_WithNewFields() {
        let tags = TagBundle(
            title: "Song",
            composer: "Bach",
            trackTotal: 10,
            discTotal: 2,
            bpm: 140,
            replayGainTrack: -2.5,
            replayGainAlbum: -1.8,
            comment: "Live recording"
        )
        XCTAssertEqual(tags.composer, "Bach")
        XCTAssertEqual(tags.trackTotal, 10)
        XCTAssertEqual(tags.discTotal, 2)
        XCTAssertEqual(tags.bpm, 140)
        XCTAssertEqual(tags.replayGainTrack ?? 0, -2.5, accuracy: 0.001)
        XCTAssertEqual(tags.replayGainAlbum ?? 0, -1.8, accuracy: 0.001)
        XCTAssertEqual(tags.comment, "Live recording")
    }

    func testEquatable_DifferentComposer() {
        let tags1 = TagBundle(title: "Song", composer: "Bach")
        let tags2 = TagBundle(title: "Song", composer: "Mozart")
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_DifferentReplayGain() {
        var tags1 = TagBundle()
        tags1.replayGainTrack = -3.0
        var tags2 = TagBundle()
        tags2.replayGainTrack = -2.0
        XCTAssertNotEqual(tags1, tags2)
    }
}
