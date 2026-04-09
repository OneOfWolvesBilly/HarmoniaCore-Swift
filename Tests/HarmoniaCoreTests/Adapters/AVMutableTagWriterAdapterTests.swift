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
