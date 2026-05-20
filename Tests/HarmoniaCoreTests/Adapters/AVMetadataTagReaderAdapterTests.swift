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
//  verify actual tag values (title, artist, year, lyrics, etc.) require real
//  audio fixtures embedded in the test bundle. Those integration tests belong
//  in a separate integration test target.
//
//  This file covers only what can be verified without real audio fixtures:
//
//  1. Protocol conformance — adapter satisfies TagReaderPort
//  2. Error handling — non-existent file throws CoreError.ioError
//
//  TagBundle field-level behaviour (storage, defaults, isEmpty semantics) is
//  covered in TagBundleTests.swift.
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
}
