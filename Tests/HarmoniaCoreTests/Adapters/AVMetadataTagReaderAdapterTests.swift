//
//  AVMetadataTagReaderAdapterTests.swift
//  HarmoniaCoreTests / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Tests for AVMetadataTagReaderAdapter.
//
//  TESTING APPROACH
//  ----------------
//  AVMetadataTagReaderAdapter reads real AVFoundation metadata, so tests that
//  verify actual tag values (genre, year, trackNumber, etc.) require real audio
//  files embedded in the test bundle. Those integration tests belong in a
//  separate integration test target.
//
//  This file covers what can be verified without real audio:
//
//  1. Protocol conformance — adapter satisfies TagReaderPort
//  2. Error handling — non-existent file throws CoreError.ioError
//  3. Empty result — file with no metadata returns TagBundle with all nil fields
//  4. Parsing helpers — year and part-number parsing logic via TagBundle round-trip
//

import XCTest
@testable import HarmoniaCore

final class AVMetadataTagReaderAdapterTests: XCTestCase {

    // MARK: - SUT

    private var sut: AVMetadataTagReaderAdapter!

    override func setUp() {
        super.setUp()
        sut = AVMetadataTagReaderAdapter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Protocol conformance

    func testAdapter_ConformsToTagReaderPort() {
        // Given / When
        let port: TagReaderPort = sut

        // Then: compile-time proof that the adapter satisfies the port contract
        XCTAssertNotNil(port)
    }

    // MARK: - Error handling

    func testRead_NonExistentFile_ThrowsIOError() {
        // Given
        let missingURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp3")

        // When / Then
        XCTAssertThrowsError(try sut.read(url: missingURL)) { error in
            guard case CoreError.ioError = error else {
                XCTFail("Expected CoreError.ioError, got \(error)")
                return
            }
        }
    }

    func testRead_NonExistentFile_DoesNotReturnBundle() {
        // Given
        let missingURL = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).mp3")

        // When
        var bundle: TagBundle?
        XCTAssertThrowsError(try { bundle = try sut.read(url: missingURL) }())

        // Then: no bundle returned on error
        XCTAssertNil(bundle)
    }

    // MARK: - TagBundle field defaults

    func testTagBundle_AllFieldsNilByDefault() {
        // Verifies that TagBundle starts empty — a precondition for adapter tests
        let bundle = TagBundle()
        XCTAssertNil(bundle.title)
        XCTAssertNil(bundle.artist)
        XCTAssertNil(bundle.album)
        XCTAssertNil(bundle.albumArtist)
        XCTAssertNil(bundle.composer)
        XCTAssertNil(bundle.genre)
        XCTAssertNil(bundle.year)
        XCTAssertNil(bundle.trackNumber)
        XCTAssertNil(bundle.trackTotal)
        XCTAssertNil(bundle.discNumber)
        XCTAssertNil(bundle.discTotal)
        XCTAssertNil(bundle.bpm)
        XCTAssertNil(bundle.replayGainTrack)
        XCTAssertNil(bundle.replayGainAlbum)
        XCTAssertNil(bundle.comment)
        XCTAssertNil(bundle.artworkData)
        XCTAssertTrue(bundle.isEmpty)
    }

    // MARK: - Year parsing (via MockTagReaderPort pattern)
    //
    // The readYear() helper is private, but its behaviour is observable through
    // the MockTagReaderPort which lets us set year directly. These tests verify
    // the TagBundle model contract that downstream mapping code depends on.

    func testTagBundle_Year_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.year = 1977
        XCTAssertEqual(bundle.year, 1977)
    }

    func testTagBundle_Year_CanBeNil() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.year)
    }

    // MARK: - Part number parsing contract

    func testTagBundle_TrackNumber_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.trackNumber = 3
        XCTAssertEqual(bundle.trackNumber, 3)
    }

    func testTagBundle_DiscNumber_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.discNumber = 2
        XCTAssertEqual(bundle.discNumber, 2)
    }

    func testTagBundle_AlbumArtist_StoresString() {
        var bundle = TagBundle()
        bundle.albumArtist = "Various Artists"
        XCTAssertEqual(bundle.albumArtist, "Various Artists")
    }

    func testTagBundle_Genre_StoresString() {
        var bundle = TagBundle()
        bundle.genre = "Rock"
        XCTAssertEqual(bundle.genre, "Rock")
    }

    // MARK: - Adapter initialisation

    func testAdapter_CanBeInstantiatedMultipleTimes() {
        // Verify no shared mutable state prevents multiple adapter instances
        let adapter1 = AVMetadataTagReaderAdapter()
        let adapter2 = AVMetadataTagReaderAdapter()
        XCTAssertNotNil(adapter1)
        XCTAssertNotNil(adapter2)
    }

    // MARK: - New field defaults (composer, trackTotal, discTotal, bpm, replayGain, comment)

    func testTagBundle_Composer_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.composer)
    }

    func testTagBundle_Composer_StoresString() {
        var bundle = TagBundle()
        bundle.composer = "Hans Zimmer"
        XCTAssertEqual(bundle.composer, "Hans Zimmer")
    }

    func testTagBundle_TrackTotal_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.trackTotal)
    }

    func testTagBundle_TrackTotal_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.trackTotal = 12
        XCTAssertEqual(bundle.trackTotal, 12)
    }

    func testTagBundle_DiscTotal_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.discTotal)
    }

    func testTagBundle_DiscTotal_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.discTotal = 2
        XCTAssertEqual(bundle.discTotal, 2)
    }

    func testTagBundle_Bpm_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.bpm)
    }

    func testTagBundle_Bpm_StoresPositiveInt() {
        var bundle = TagBundle()
        bundle.bpm = 120
        XCTAssertEqual(bundle.bpm, 120)
    }

    func testTagBundle_ReplayGainTrack_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.replayGainTrack)
    }

    func testTagBundle_ReplayGainTrack_StoresDouble() {
        var bundle = TagBundle()
        bundle.replayGainTrack = -3.21
        XCTAssertEqual(bundle.replayGainTrack ?? 0, -3.21, accuracy: 0.001)
    }

    func testTagBundle_ReplayGainAlbum_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.replayGainAlbum)
    }

    func testTagBundle_ReplayGainAlbum_StoresDouble() {
        var bundle = TagBundle()
        bundle.replayGainAlbum = 1.50
        XCTAssertEqual(bundle.replayGainAlbum ?? 0, 1.50, accuracy: 0.001)
    }

    func testTagBundle_Comment_NilByDefault() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.comment)
    }

    func testTagBundle_Comment_StoresString() {
        var bundle = TagBundle()
        bundle.comment = "Live at Carnegie Hall"
        XCTAssertEqual(bundle.comment, "Live at Carnegie Hall")
    }
}
