//
//  AVMutableTagWriterAdapterTests.swift
//  HarmoniaCoreTests / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Tests for AVMutableTagWriterAdapter.
//
//  TESTING APPROACH
//  ----------------
//  AVMutableTagWriterAdapter writes real files via AVFoundation export session,
//  so tests that verify actual written tag values require real audio files.
//  Those integration tests belong in a separate integration test target.
//
//  This file covers what can be verified without real audio files by calling
//  the internal buildMetadataItems(from:) method directly:
//
//  1. Protocol conformance — adapter satisfies TagWriterPort
//  2. Unsupported format check — flac/dsf/dff throw before file I/O
//  3. Metadata items — all TagBundle fields produce correct AVMetadataIdentifiers
//  4. ReplayGain — silently skipped, not included in metadata items
//  5. Track/disc number format — "N/T" string format
//  6. Adapter instantiation — multiple instances allowed
//

import XCTest
import AVFoundation
@testable import HarmoniaCore

final class AVMutableTagWriterAdapterTests: XCTestCase {

    // MARK: - SUT

    private var sut: AVMutableTagWriterAdapter!

    override func setUp() {
        super.setUp()
        sut = AVMutableTagWriterAdapter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Protocol conformance

    func testAdapter_ConformsToTagWriterPort() {
        let port: TagWriterPort = sut
        XCTAssertNotNil(port)
    }

    // MARK: - Unsupported format check (before file I/O)

    func testWrite_FlacFile_ThrowsUnsupportedBeforeFileIO() {
        // File does not exist — if extension check comes first, throws unsupported.
        // If no extension check, would throw ioError instead.
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).flac")
        XCTAssertThrowsError(try sut.write(url: url, tags: TagBundle())) { error in
            guard case CoreError.unsupported = error else {
                XCTFail("Expected CoreError.unsupported before file I/O, got \(error)")
                return
            }
        }
    }

    func testWrite_DsfFile_ThrowsUnsupportedBeforeFileIO() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).dsf")
        XCTAssertThrowsError(try sut.write(url: url, tags: TagBundle())) { error in
            guard case CoreError.unsupported = error else {
                XCTFail("Expected CoreError.unsupported before file I/O, got \(error)")
                return
            }
        }
    }

    func testWrite_DffFile_ThrowsUnsupportedBeforeFileIO() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).dff")
        XCTAssertThrowsError(try sut.write(url: url, tags: TagBundle())) { error in
            guard case CoreError.unsupported = error else {
                XCTFail("Expected CoreError.unsupported before file I/O, got \(error)")
                return
            }
        }
    }

    // MARK: - Metadata items: core fields (currently implemented)

    func testBuildMetadataItems_Title_UsesCommonIdentifier() {
        var tags = TagBundle()
        tags.title = "Bohemian Rhapsody"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .commonIdentifierTitle),
                      "Expected commonIdentifierTitle")
    }

    func testBuildMetadataItems_Artist_UsesCommonIdentifier() {
        var tags = TagBundle()
        tags.artist = "Queen"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .commonIdentifierArtist),
                      "Expected commonIdentifierArtist")
    }

    func testBuildMetadataItems_Album_UsesCommonIdentifier() {
        var tags = TagBundle()
        tags.album = "A Night at the Opera"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .commonIdentifierAlbumName),
                      "Expected commonIdentifierAlbumName")
    }

    func testBuildMetadataItems_Artwork_UsesCommonIdentifier() {
        var tags = TagBundle()
        tags.artworkData = Data([0xFF, 0xD8, 0xFF])
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .commonIdentifierArtwork),
                      "Expected commonIdentifierArtwork")
    }

    // MARK: - Metadata items: extended fields (currently NOT implemented → red)

    func testBuildMetadataItems_AlbumArtist_UsesID3MetadataBand() {
        var tags = TagBundle()
        tags.albumArtist = "Various Artists"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataBand),
                      "Expected id3MetadataBand (TPE2) for albumArtist")
    }

    func testBuildMetadataItems_Composer_UsesID3MetadataComposer() {
        var tags = TagBundle()
        tags.composer = "Freddie Mercury"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataComposer),
                      "Expected id3MetadataComposer (TCOM) for composer")
    }

    func testBuildMetadataItems_Genre_UsesID3MetadataContentType() {
        var tags = TagBundle()
        tags.genre = "Rock"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataContentType),
                      "Expected id3MetadataContentType (TCON) for genre")
    }

    func testBuildMetadataItems_Year_UsesID3MetadataRecordingTime() {
        var tags = TagBundle()
        tags.year = 1975
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataRecordingTime),
                      "Expected id3MetadataRecordingTime (TDRC) for year")
    }

    func testBuildMetadataItems_TrackNumber_UsesID3MetadataTrackNumber() {
        var tags = TagBundle()
        tags.trackNumber = 3
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataTrackNumber),
                      "Expected id3MetadataTrackNumber (TRCK) for trackNumber")
    }

    func testBuildMetadataItems_TrackNumber_WithTotal_FormatsAsNSlashT() {
        var tags = TagBundle()
        tags.trackNumber = 3
        tags.trackTotal = 12
        let items = sut.buildMetadataItems(from: tags)
        let item = items.first { $0.identifier == .id3MetadataTrackNumber }
        XCTAssertNotNil(item, "Expected id3MetadataTrackNumber item")
        XCTAssertEqual(item?.value as? String, "3/12",
                       "Expected 'N/T' format for track number with total")
    }

    func testBuildMetadataItems_DiscNumber_UsesID3MetadataPartOfASet() {
        var tags = TagBundle()
        tags.discNumber = 1
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataPartOfASet),
                      "Expected id3MetadataPartOfASet (TPOS) for discNumber")
    }

    func testBuildMetadataItems_DiscNumber_WithTotal_FormatsAsNSlashT() {
        var tags = TagBundle()
        tags.discNumber = 1
        tags.discTotal = 2
        let items = sut.buildMetadataItems(from: tags)
        let item = items.first { $0.identifier == .id3MetadataPartOfASet }
        XCTAssertNotNil(item, "Expected id3MetadataPartOfASet item")
        XCTAssertEqual(item?.value as? String, "1/2",
                       "Expected 'N/T' format for disc number with total")
    }

    func testBuildMetadataItems_Bpm_UsesID3MetadataBeatsPerMinute() {
        var tags = TagBundle()
        tags.bpm = 120
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataBeatsPerMinute),
                      "Expected id3MetadataBeatsPerMinute (TBPM) for bpm")
    }

    func testBuildMetadataItems_Comment_UsesID3MetadataComments() {
        var tags = TagBundle()
        tags.comment = "Live at Carnegie Hall"
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertTrue(containsIdentifier(items, .id3MetadataComments),
                      "Expected id3MetadataComments (COMM) for comment")
    }

    // MARK: - ReplayGain silently skipped

    func testBuildMetadataItems_ReplayGain_NotIncluded() {
        var tags = TagBundle()
        tags.replayGainTrack = -3.21
        tags.replayGainAlbum = -1.50
        let items = sut.buildMetadataItems(from: tags)
        XCTAssertFalse(containsIdentifier(items, .id3MetadataUserText),
                       "ReplayGain must be silently skipped, not written as TXXX")
    }

    // MARK: - Empty TagBundle produces no items

    func testBuildMetadataItems_EmptyBundle_ReturnsEmpty() {
        let items = sut.buildMetadataItems(from: TagBundle())
        XCTAssertTrue(items.isEmpty, "Empty TagBundle should produce no metadata items")
    }

    // MARK: - Adapter instantiation

    func testAdapter_CanBeInstantiatedMultipleTimes() {
        let adapter1 = AVMutableTagWriterAdapter()
        let adapter2 = AVMutableTagWriterAdapter()
        XCTAssertNotNil(adapter1)
        XCTAssertNotNil(adapter2)
    }

    // MARK: - File replacement preserves attributes (Slice 9-B)
    //
    // write() uses an internal helper replaceFile(at:withTempFileAt:) to swap
    // the export session's temp output onto the original URL. The helper must
    // preserve the original file's extended attributes, creation date, and
    // other POSIX/ACL metadata — this is the fix for the pre-9-B bug where
    // removeItem + moveItem silently dropped xattr (including
    // kMDItemWhereFroms) and reset the creation date to "now".
    //
    // These tests exercise the helper directly with plain binary files so
    // that no real audio fixture or AVFoundation export is required.

    #if os(macOS)

    func testReplaceFile_PreservesXattr() throws {
        // Given: original file with a kMDItemWhereFroms-style xattr, and a
        // temp file that will replace it.
        let tempDir = FileManager.default.temporaryDirectory
        let originalURL = tempDir.appendingPathComponent("hc-orig-\(UUID().uuidString).bin")
        let tempURL = tempDir.appendingPathComponent("hc-temp-\(UUID().uuidString).bin")

        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: tempURL)
        }

        try Data([0x01, 0x02, 0x03]).write(to: originalURL)
        try Data([0x04, 0x05, 0x06]).write(to: tempURL)

        let key = "com.apple.metadata:kMDItemWhereFroms"
        let xattrPayload = Data([0xAA, 0xBB, 0xCC])
        let setResult = xattrPayload.withUnsafeBytes { bytes in
            setxattr(originalURL.path, key, bytes.baseAddress, xattrPayload.count, 0, 0)
        }
        XCTAssertEqual(setResult, 0,
                       "setxattr preparation failed with errno \(errno)")

        // When: replacing the original file using the helper under test.
        try sut.replaceFile(at: originalURL, withTempFileAt: tempURL)

        // Then: the xattr must still be present on the replaced file.
        let size = getxattr(originalURL.path, key, nil, 0, 0, 0)
        XCTAssertGreaterThan(size, 0,
                             "xattr must be preserved after file replacement")

        var buffer = [UInt8](repeating: 0, count: size)
        let readSize = getxattr(originalURL.path, key, &buffer, size, 0, 0)
        XCTAssertEqual(readSize, size)
        XCTAssertEqual(Array(xattrPayload), buffer,
                       "xattr payload must match the original value")
    }

    func testReplaceFile_PreservesCreationDate() throws {
        // Given: original file whose creation date has been explicitly set
        // to a past date, and a fresh temp file whose creation date is
        // naturally "now".
        let tempDir = FileManager.default.temporaryDirectory
        let originalURL = tempDir.appendingPathComponent("hc-orig-\(UUID().uuidString).bin")
        let tempURL = tempDir.appendingPathComponent("hc-temp-\(UUID().uuidString).bin")

        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: tempURL)
        }

        try Data([0x01]).write(to: originalURL)
        try Data([0x02]).write(to: tempURL)

        // 2020-01-01 00:00:00 UTC — clearly in the past so "now" vs expected
        // cannot collide within the XCTAssertEqual accuracy window.
        let expected = Date(timeIntervalSince1970: 1_577_836_800)
        try FileManager.default.setAttributes(
            [.creationDate: expected],
            ofItemAtPath: originalURL.path
        )

        // When
        try sut.replaceFile(at: originalURL, withTempFileAt: tempURL)

        // Then: the creation date must match the original file's, not "now"
        // (which would be the result of the pre-9-B removeItem + moveItem).
        let attrs = try FileManager.default.attributesOfItem(atPath: originalURL.path)
        let actual = attrs[.creationDate] as? Date
        XCTAssertNotNil(actual,
                        "creation date must be readable after replacement")
        XCTAssertEqual(actual?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970,
                       accuracy: 1.0,
                       "creation date must be preserved, not reset to 'now'")
    }

    #endif

    // MARK: - iOS platform

    #if os(iOS)
    func testWrite_OnIOS_ThrowsUnsupported() {
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        XCTAssertThrowsError(try sut.write(url: url, tags: TagBundle())) { error in
            guard case CoreError.unsupported = error else {
                XCTFail("Expected CoreError.unsupported on iOS, got \(error)")
                return
            }
        }
    }
    #endif

    // MARK: - Helpers

    private func containsIdentifier(
        _ items: [AVMutableMetadataItem],
        _ identifier: AVMetadataIdentifier
    ) -> Bool {
        items.contains { $0.identifier == identifier }
    }
}
