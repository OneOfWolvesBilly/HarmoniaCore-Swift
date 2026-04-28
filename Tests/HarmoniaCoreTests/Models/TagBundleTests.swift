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
        XCTAssertNil(tags.duration)
        XCTAssertNil(tags.bitrate)
        XCTAssertNil(tags.sampleRate)
        XCTAssertNil(tags.channels)
        XCTAssertNil(tags.fileSize)
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

    /// Technical info fields do NOT affect isEmpty — they are stream properties,
    /// not user-facing tag metadata.
    func testIsEmpty_WithOnlyDuration_StillEmpty() {
        var tags = TagBundle()
        tags.duration = 180.0
        XCTAssertTrue(tags.isEmpty, "duration is technical info, not a tag — isEmpty should remain true")
    }

    func testIsEmpty_WithOnlyBitrate_StillEmpty() {
        var tags = TagBundle()
        tags.bitrate = 320
        XCTAssertTrue(tags.isEmpty, "bitrate is technical info, not a tag — isEmpty should remain true")
    }

    func testIsEmpty_WithOnlySampleRate_StillEmpty() {
        var tags = TagBundle()
        tags.sampleRate = 44100.0
        XCTAssertTrue(tags.isEmpty, "sampleRate is technical info, not a tag — isEmpty should remain true")
    }

    func testIsEmpty_WithOnlyChannels_StillEmpty() {
        var tags = TagBundle()
        tags.channels = 2
        XCTAssertTrue(tags.isEmpty, "channels is technical info, not a tag — isEmpty should remain true")
    }

    func testIsEmpty_WithOnlyFileSize_StillEmpty() {
        var tags = TagBundle()
        tags.fileSize = 5_000_000
        XCTAssertTrue(tags.isEmpty, "fileSize is technical info, not a tag — isEmpty should remain true")
    }

    func testIsEmpty_WithAllTechnicalInfoOnly_StillEmpty() {
        var tags = TagBundle()
        tags.duration = 240.5
        tags.bitrate = 256
        tags.sampleRate = 48000.0
        tags.channels = 2
        tags.fileSize = 8_000_000
        XCTAssertTrue(tags.isEmpty, "only technical info set — isEmpty should remain true")
    }

    func testIsEmpty_WithTitleAndTechnicalInfo_NotEmpty() {
        var tags = TagBundle()
        tags.title = "Song"
        tags.duration = 180.0
        tags.bitrate = 320
        XCTAssertFalse(tags.isEmpty, "title is a tag — isEmpty should be false")
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

    func testEquatable_DifferentDuration() {
        let tags1 = TagBundle(title: "Song", duration: 180.0)
        let tags2 = TagBundle(title: "Song", duration: 200.0)
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_DifferentBitrate() {
        let tags1 = TagBundle(title: "Song", bitrate: 320)
        let tags2 = TagBundle(title: "Song", bitrate: 256)
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_DifferentSampleRate() {
        let tags1 = TagBundle(title: "Song", sampleRate: 44100.0)
        let tags2 = TagBundle(title: "Song", sampleRate: 48000.0)
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_DifferentChannels() {
        let tags1 = TagBundle(title: "Song", channels: 1)
        let tags2 = TagBundle(title: "Song", channels: 2)
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_DifferentFileSize() {
        let tags1 = TagBundle(title: "Song", fileSize: 1_000_000)
        let tags2 = TagBundle(title: "Song", fileSize: 2_000_000)
        XCTAssertNotEqual(tags1, tags2)
    }

    func testEquatable_SameTechnicalInfo() {
        let tags1 = TagBundle(duration: 180.0, bitrate: 320, sampleRate: 44100.0, channels: 2, fileSize: 5_000_000)
        let tags2 = TagBundle(duration: 180.0, bitrate: 320, sampleRate: 44100.0, channels: 2, fileSize: 5_000_000)
        XCTAssertEqual(tags1, tags2)
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

    // MARK: - Technical Info Field Tests

    func testDuration_StoresTimeInterval() {
        var tags = TagBundle()
        tags.duration = 245.7
        XCTAssertEqual(tags.duration ?? 0, 245.7, accuracy: 0.001)
    }

    func testBitrate_StoresKbps() {
        var tags = TagBundle()
        tags.bitrate = 320
        XCTAssertEqual(tags.bitrate, 320)
    }

    func testSampleRate_StoresHz() {
        var tags = TagBundle()
        tags.sampleRate = 44100.0
        XCTAssertEqual(tags.sampleRate ?? 0, 44100.0, accuracy: 0.001)
    }

    func testChannels_StoresInt() {
        var tags = TagBundle()
        tags.channels = 2
        XCTAssertEqual(tags.channels, 2)
    }

    func testFileSize_StoresBytes() {
        var tags = TagBundle()
        tags.fileSize = 8_543_210
        XCTAssertEqual(tags.fileSize, 8_543_210)
    }

    func testInitialization_WithTechnicalInfoFields() {
        let tags = TagBundle(
            title: "Song",
            duration: 180.5,
            bitrate: 256,
            sampleRate: 48000.0,
            channels: 2,
            fileSize: 5_500_000
        )
        XCTAssertEqual(tags.title, "Song")
        XCTAssertEqual(tags.duration ?? 0, 180.5, accuracy: 0.001)
        XCTAssertEqual(tags.bitrate, 256)
        XCTAssertEqual(tags.sampleRate ?? 0, 48000.0, accuracy: 0.001)
        XCTAssertEqual(tags.channels, 2)
        XCTAssertEqual(tags.fileSize, 5_500_000)
    }

    func testInitialization_WithAllFields() {
        let tags = TagBundle(
            title: "Full Song",
            artist: "Artist",
            album: "Album",
            albumArtist: "AlbumArtist",
            composer: "Composer",
            genre: "Rock",
            year: 2024,
            trackNumber: 3,
            trackTotal: 12,
            discNumber: 1,
            discTotal: 2,
            bpm: 120,
            replayGainTrack: -3.5,
            replayGainAlbum: -1.2,
            comment: "Note",
            artworkData: Data([0x89, 0x50]),
            duration: 300.0,
            bitrate: 320,
            sampleRate: 44100.0,
            channels: 2,
            fileSize: 12_000_000
        )
        XCTAssertEqual(tags.title, "Full Song")
        XCTAssertEqual(tags.duration ?? 0, 300.0, accuracy: 0.001)
        XCTAssertEqual(tags.bitrate, 320)
        XCTAssertEqual(tags.sampleRate ?? 0, 44100.0, accuracy: 0.001)
        XCTAssertEqual(tags.channels, 2)
        XCTAssertEqual(tags.fileSize, 12_000_000)
        XCTAssertFalse(tags.isEmpty)
    }

    // MARK: - Schema Version Tests

    func testCurrentSchemaVersion_IsPositive() {
        XCTAssertGreaterThan(TagBundle.currentSchemaVersion, 0,
                             "currentSchemaVersion must be > 0")
    }

    func testCurrentSchemaVersion_EqualsTwo() {
        XCTAssertEqual(TagBundle.currentSchemaVersion, 2,
                       "currentSchemaVersion should be 2 after adding codec and encoding fields")
    }

    // MARK: - Codec / Encoding Tests

    func testTagBundle_Codec_DefaultNil() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.codec)
    }

    func testTagBundle_Encoding_DefaultNil() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.encoding)
    }

    func testTagBundle_Codec_StoresString() {
        var bundle = TagBundle()
        bundle.codec = "AAC LC"
        XCTAssertEqual(bundle.codec, "AAC LC")
    }

    func testTagBundle_Encoding_StoresString() {
        var bundle = TagBundle()
        bundle.encoding = "lossy"
        XCTAssertEqual(bundle.encoding, "lossy")
    }

    func testIsEmpty_WithOnlyCodec_StillEmpty() {
        var bundle = TagBundle()
        bundle.codec = "MP3 Layer 3"
        XCTAssertTrue(bundle.isEmpty,
                      "codec is technical info, not a tag field — should not affect isEmpty")
    }

    func testIsEmpty_WithOnlyEncoding_StillEmpty() {
        var bundle = TagBundle()
        bundle.encoding = "lossless"
        XCTAssertTrue(bundle.isEmpty,
                      "encoding is technical info, not a tag field — should not affect isEmpty")
    }

    func testEquatable_DifferentCodec() {
        var a = TagBundle()
        var b = TagBundle()
        a.codec = "AAC LC"
        b.codec = "MP3 Layer 3"
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_DifferentEncoding() {
        var a = TagBundle()
        var b = TagBundle()
        a.encoding = "lossy"
        b.encoding = "lossless"
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Lyrics field tests (Slice 9-J)

    func testTagBundle_Lyrics_DefaultNil() {
        let bundle = TagBundle()
        XCTAssertNil(bundle.lyrics)
    }

    func testTagBundle_Lyrics_StoresSingleVariant() {
        var bundle = TagBundle()
        bundle.lyrics = [LyricsLanguageVariant(languageCode: "eng", text: "hello")]
        XCTAssertEqual(bundle.lyrics?.count, 1)
        XCTAssertEqual(bundle.lyrics?.first?.text, "hello")
        XCTAssertEqual(bundle.lyrics?.first?.languageCode, "eng")
    }

    func testTagBundle_Lyrics_StoresMultipleVariants() {
        var bundle = TagBundle()
        bundle.lyrics = [
            LyricsLanguageVariant(languageCode: "eng", text: "Hello"),
            LyricsLanguageVariant(languageCode: "chi", text: "你好")
        ]
        XCTAssertEqual(bundle.lyrics?.count, 2)
    }

    func testTagBundle_Lyrics_NilLanguageCode_IsStored() {
        var bundle = TagBundle()
        bundle.lyrics = [LyricsLanguageVariant(languageCode: nil, text: "undeclared")]
        XCTAssertNil(bundle.lyrics?.first?.languageCode)
        XCTAssertEqual(bundle.lyrics?.first?.text, "undeclared")
    }

    func testIsEmpty_WithLyrics_NotEmpty() {
        var bundle = TagBundle()
        bundle.lyrics = [LyricsLanguageVariant(languageCode: nil, text: "some lyrics")]
        XCTAssertFalse(bundle.isEmpty, "lyrics is a user-facing tag field — isEmpty should be false")
    }

    func testEquatable_DifferentLyrics_AreNotEqual() {
        var a = TagBundle()
        var b = TagBundle()
        a.lyrics = [LyricsLanguageVariant(languageCode: "eng", text: "Hello")]
        b.lyrics = [LyricsLanguageVariant(languageCode: "eng", text: "World")]
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_SameLyrics_AreEqual() {
        var a = TagBundle()
        var b = TagBundle()
        a.lyrics = [LyricsLanguageVariant(languageCode: "eng", text: "Hello")]
        b.lyrics = [LyricsLanguageVariant(languageCode: "eng", text: "Hello")]
        XCTAssertEqual(a, b)
    }

    func testInitialization_WithLyrics_StoresValue() {
        let variant = LyricsLanguageVariant(languageCode: "jpn", text: "こんにちは")
        let bundle = TagBundle(lyrics: [variant])
        XCTAssertEqual(bundle.lyrics?.count, 1)
        XCTAssertEqual(bundle.lyrics?.first?.languageCode, "jpn")
    }
}