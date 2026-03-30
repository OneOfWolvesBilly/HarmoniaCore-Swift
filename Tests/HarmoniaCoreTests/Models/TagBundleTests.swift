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
        XCTAssertNil(tags.genre)
        XCTAssertNil(tags.year)
        XCTAssertNil(tags.trackNumber)
        XCTAssertNil(tags.discNumber)
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
    
    // MARK: - New fields (Slice 7-H)
    
    func testTagBundle_Composer_StoresString() {
        var tags = TagBundle()
        tags.composer = "Freddie Mercury"
        XCTAssertEqual(tags.composer, "Freddie Mercury")
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_TrackTotal_StoresPositiveInt() {
        var tags = TagBundle()
        tags.trackTotal = 12
        XCTAssertEqual(tags.trackTotal, 12)
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_DiscTotal_StoresPositiveInt() {
        var tags = TagBundle()
        tags.discTotal = 2
        XCTAssertEqual(tags.discTotal, 2)
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_BPM_StoresPositiveInt() {
        var tags = TagBundle()
        tags.bpm = 128
        XCTAssertEqual(tags.bpm, 128)
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_Comment_StoresString() {
        var tags = TagBundle()
        tags.comment = "Live version"
        XCTAssertEqual(tags.comment, "Live version")
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_ReplayGainTrack_StoresDouble() throws {
        var tags = TagBundle()
        tags.replayGainTrack = -5.32
        let value = try XCTUnwrap(tags.replayGainTrack)
        XCTAssertEqual(value, -5.32, accuracy: 0.001)
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_ReplayGainAlbum_StoresDouble() throws {
        var tags = TagBundle()
        tags.replayGainAlbum = -4.10
        let value = try XCTUnwrap(tags.replayGainAlbum)
        XCTAssertEqual(value, -4.10, accuracy: 0.001)
        XCTAssertFalse(tags.isEmpty)
    }
    
    func testTagBundle_AllNewFieldsNilByDefault() {
        let tags = TagBundle()
        XCTAssertNil(tags.composer)
        XCTAssertNil(tags.trackTotal)
        XCTAssertNil(tags.discTotal)
        XCTAssertNil(tags.bpm)
        XCTAssertNil(tags.comment)
        XCTAssertNil(tags.replayGainTrack)
        XCTAssertNil(tags.replayGainAlbum)
    }
    
    func testTagBundle_IsEmpty_NewFieldsIncluded() {
        var tags = TagBundle()
        XCTAssertTrue(tags.isEmpty)
        tags.bpm = 120
        XCTAssertFalse(tags.isEmpty)
    }
}
