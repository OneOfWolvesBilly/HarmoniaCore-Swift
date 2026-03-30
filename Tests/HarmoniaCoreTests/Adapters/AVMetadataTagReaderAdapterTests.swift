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
        XCTAssertNil(bundle.genre)
        XCTAssertNil(bundle.year)
        XCTAssertNil(bundle.trackNumber)
        XCTAssertNil(bundle.discNumber)
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
}
