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
}
