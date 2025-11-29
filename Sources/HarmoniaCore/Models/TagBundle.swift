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
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
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
               genre == nil &&
               year == nil &&
               trackNumber == nil &&
               discNumber == nil &&
               artworkData == nil
    }
}
