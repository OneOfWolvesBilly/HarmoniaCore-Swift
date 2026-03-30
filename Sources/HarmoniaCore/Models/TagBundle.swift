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
    public var comment: String?
    public var replayGainTrack: Double?
    public var replayGainAlbum: Double?
    public var artworkData: Data?

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
        comment: String? = nil,
        replayGainTrack: Double? = nil,
        replayGainAlbum: Double? = nil,
        artworkData: Data? = nil
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
        self.comment = comment
        self.replayGainTrack = replayGainTrack
        self.replayGainAlbum = replayGainAlbum
        self.artworkData = artworkData
    }
}

// MARK: - Helpers

extension TagBundle {
    /// Returns true if all fields are nil
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
               comment == nil &&
               replayGainTrack == nil &&
               replayGainAlbum == nil &&
               artworkData == nil
    }
}
