//
//  AVMetadataTagReaderAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Swift 6 compatible using @preconcurrency.
//  Supports macOS 13+ / iOS 16+
//
//  READING STRATEGY
//  ----------------
//  Two metadata collections are loaded from the asset:
//
//  1. asset.load(.commonMetadata)
//     Cross-format common keys. Used for: title, artist, album, artwork.
//
//  2. asset.load(.metadata)
//     Format-specific keys (iTunes / ID3).
//     Required for: albumArtist, genre, year, trackNumber, discNumber.
//     commonMetadata does not expose these fields reliably.
//
//  See specs/02_01_apple.adapters.md for the full field→identifier table.

import Foundation
@preconcurrency import AVFoundation

public final class AVMetadataTagReaderAdapter: TagReaderPort {
    
    public init() {}
    
    public func read(url: URL) throws -> TagBundle {
        let asset = AVURLAsset(url: url)
        
        // ── Step 1: Load commonMetadata (title, artist, album, artwork) ──
        
        nonisolated(unsafe) var commonItems: [AVMetadataItem] = []
        nonisolated(unsafe) var loadError: Error?
        
        let sema1 = DispatchSemaphore(value: 0)
        Task { @Sendable in
            do { commonItems = try await asset.load(.commonMetadata) }
            catch { loadError = error }
            sema1.signal()
        }
        sema1.wait()
        
        if let error = loadError {
            throw CoreError.ioError(underlying: error)
        }
        
        // ── Step 2: Load all metadata (albumArtist, genre, year, numbers) ─
        // Non-fatal: if this fails, extended fields remain nil.
        
        nonisolated(unsafe) var allItems: [AVMetadataItem] = []
        let sema2 = DispatchSemaphore(value: 0)
        Task { @Sendable in
            allItems = (try? await asset.load(.metadata)) ?? []
            sema2.signal()
        }
        sema2.wait()
        
        // ── Step 3: Build TagBundle ───────────────────────────────────────
        
        var bundle = TagBundle()
        
        // Core fields from commonMetadata
        for item in commonItems {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                bundle.title = loadString(from: item)
            case .commonKeyArtist:
                bundle.artist = loadString(from: item)
            case .commonKeyAlbumName:
                bundle.album = loadString(from: item)
            default:
                break
            }
        }
        
        // Artwork from commonMetadata
        if let artworkItem = AVMetadataItem.metadataItems(
            from: commonItems,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first {
            bundle.artworkData = loadData(from: artworkItem)
        }
        
        // Extended fields from format-specific metadata
        bundle.albumArtist = readString(from: allItems, identifiers: [
            .iTunesMetadataAlbumArtist,
            .id3MetadataBand                    // TPE2
        ])
        
        bundle.genre = readString(from: allItems, identifiers: [
            .iTunesMetadataUserGenre,
            .iTunesMetadataPredefinedGenre,
            .id3MetadataContentType             // TCON
        ])
        
        bundle.year = readYear(from: allItems)
        
        bundle.trackNumber = readPartNumber(from: allItems, identifiers: [
            .iTunesMetadataTrackNumber,
            .id3MetadataTrackNumber             // TRCK
        ])
        
        // discNumber: AVMetadataIdentifier has no named constant for iTunes disc number.
        // Use the key+keySpace API with the known AVMetadataKey constant instead.
        bundle.discNumber = readPartNumberByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyDiscNumber,
            keySpace: .iTunes
        )
        
        return bundle
    }
    
    // MARK: - Private helpers
    
    /// Synchronously loads the string value of a single metadata item.
    private func loadString(from item: AVMetadataItem) -> String? {
        let sema = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: String?
        Task { @Sendable in
            result = try? await item.load(.stringValue)
            sema.signal()
        }
        sema.wait()
        return result
    }
    
    /// Synchronously loads the data value of a single metadata item.
    private func loadData(from item: AVMetadataItem) -> Data? {
        let sema = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Data?
        Task { @Sendable in
            result = try? await item.load(.dataValue)
            sema.signal()
        }
        sema.wait()
        return result
    }
    
    /// Returns the first non-empty string matching any of the given identifiers,
    /// trying each identifier in order.
    private func readString(
        from items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) -> String? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first),
               !s.isEmpty {
                return s
            }
        }
        return nil
    }
    
    /// Parses a year integer from release-date / year metadata identifiers.
    ///
    /// Handles ISO-8601 dates ("1977-05-25") and bare year strings ("1977").
    /// Takes the first 4 characters and converts to `Int`.
    /// Returns `nil` if no valid positive year is found.
    private func readYear(from items: [AVMetadataItem]) -> Int? {
        let identifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataReleaseDate,
            .id3MetadataRecordingTime,          // TDRC (ID3v2.4)
            .id3MetadataYear,                   // TYER (ID3v2.3)
            .commonIdentifierCreationDate
        ]
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first) {
                let yearStr = String(s.prefix(4))
                if let y = Int(yearStr), y > 0 { return y }
            }
        }
        return nil
    }
    
    /// Parses the first part of a "N/total" track or disc number string.
    ///
    /// Examples: `"3/12"` → `3`, `"3"` → `3`.
    /// Returns `nil` if the parsed value is 0 or negative.
    private func readPartNumber(
        from items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) -> Int? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first) {
                if let n = parsePartNumber(from: s) { return n }
            }
        }
        return nil
    }
    
    /// Variant of `readPartNumber` that uses `AVMetadataKey` + `AVMetadataKeySpace`
    /// instead of `AVMetadataIdentifier`.
    ///
    /// Required for iTunes fields that have an `AVMetadataKey` constant but no
    /// corresponding named `AVMetadataIdentifier` constant (e.g. disc number).
    private func readPartNumberByKey(
        from items: [AVMetadataItem],
        key: AVMetadataKey,
        keySpace: AVMetadataKeySpace
    ) -> Int? {
        let matches = AVMetadataItem.metadataItems(from: items,
                                                   withKey: key,
                                                   keySpace: keySpace)
        if let first = matches.first,
           let s = loadString(from: first) {
            return parsePartNumber(from: s)
        }
        return nil
    }
    
    /// Parses "N" or "N/total" into the N component.
    /// Returns `nil` if N is 0 or negative.
    private func parsePartNumber(from s: String) -> Int? {
        let part = s.split(separator: "/").first.map(String.init) ?? s
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n > 0 { return n }
        return nil
    }
}
