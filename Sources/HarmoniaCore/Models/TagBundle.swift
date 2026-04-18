//
//  TagBundle.swift
//  HarmoniaCore / Models
//
//  SPDX-License-Identifier: MIT
//
//  Represents metadata tags for audio assets.
//  Conforms to specification in docs/specs/05_models.md
//
import Foundation

public struct TagBundle: Sendable, Equatable {

    // MARK: - Schema Version

    /// Current schema version for TagBundle.
    ///
    /// Consumers (e.g. HarmoniaPlayer) use this to detect tracks that were
    /// persisted by an older schema and trigger background metadata re-reads.
    ///
    /// History:
    /// - 0: legacy (no technical info fields)
    /// - 1: added duration, bitrate, sampleRate, channels, fileSize
    /// - 2: added codec, encoding
    public static let currentSchemaVersion: Int = 2

    // MARK: - Tag Fields

    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var composer: String?
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var bpm: Int?
    public var replayGainTrack: Double?
    public var replayGainAlbum: Double?
    public var comment: String?
    public var artworkData: Data?

    // MARK: - Technical Info Fields
    //
    // These fields describe audio stream and file properties that are
    // read alongside tags from the same AVURLAsset. They are NOT tag
    // metadata in the ID3/MP4 sense and are excluded from `isEmpty`.

    /// Audio codec name, e.g. "MP3 Layer 3", "AAC LC", "Apple Lossless (ALAC)",
    /// "FLAC", "PCM". Derived from AVFoundation's `CMAudioFormatDescription`
    /// (`mFormatID` and AAC object type from `formatSpecificInfo` when applicable).
    /// `nil` if the codec cannot be determined.
    public var codec: String?

    /// Audio encoding classification, one of `"lossy"` or `"lossless"`.
    /// Derived from `codec`. `nil` if codec is unknown.
    public var encoding: String?

    /// Duration of the audio file in seconds. `nil` if unavailable.
    public var duration: TimeInterval?

    /// Estimated bitrate in kbps (kilobits per second). `nil` if unavailable.
    public var bitrate: Int?

    /// Sample rate in Hz (e.g. 44100.0, 48000.0). `nil` if unavailable.
    public var sampleRate: Double?

    /// Number of audio channels (e.g. 1 = mono, 2 = stereo). `nil` if unavailable.
    public var channels: Int?

    /// File size in bytes. `nil` if unavailable or non-file URL.
    public var fileSize: Int?

    // MARK: - Initialization

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        composer: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        bpm: Int? = nil,
        replayGainTrack: Double? = nil,
        replayGainAlbum: Double? = nil,
        comment: String? = nil,
        artworkData: Data? = nil,
        codec: String? = nil,
        encoding: String? = nil,
        duration: TimeInterval? = nil,
        bitrate: Int? = nil,
        sampleRate: Double? = nil,
        channels: Int? = nil,
        fileSize: Int? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.bpm = bpm
        self.replayGainTrack = replayGainTrack
        self.replayGainAlbum = replayGainAlbum
        self.comment = comment
        self.artworkData = artworkData
        self.codec = codec
        self.encoding = encoding
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.fileSize = fileSize
    }
}

// MARK: - Helpers

extension TagBundle {
    /// Returns true if all tag fields are nil.
    ///
    /// Technical info fields (codec, encoding, duration, bitrate, sampleRate,
    /// channels, fileSize) are excluded because they describe the audio stream,
    /// not user-facing tags. A file with no ID3/MP4 tags but valid duration
    /// is still considered "empty" from a tagging perspective.
    public var isEmpty: Bool {
        return title == nil &&
               artist == nil &&
               album == nil &&
               albumArtist == nil &&
               composer == nil &&
               genre == nil &&
               year == nil &&
               trackNumber == nil &&
               trackTotal == nil &&
               discNumber == nil &&
               discTotal == nil &&
               bpm == nil &&
               replayGainTrack == nil &&
               replayGainAlbum == nil &&
               comment == nil &&
               artworkData == nil
    }
}
