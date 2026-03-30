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

        bundle.composer = readString(from: allItems, identifiers: [
            .iTunesMetadataComposer,
            .id3MetadataComposer                // TCOM
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
        bundle.trackTotal = readPartTotal(from: allItems, identifiers: [
            .iTunesMetadataTrackNumber,
            .id3MetadataTrackNumber             // TRCK
        ])

        // discNumber / discTotal: AVMetadataIdentifier has no named constant for
        // iTunes disc number; use key+keySpace API, then fall back to ID3 TPOS.
        bundle.discNumber = readPartNumberByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyDiscNumber,
            keySpace: .iTunes
        ) ?? readPartNumber(from: allItems, identifiers: [.id3MetadataPartOfASet])

        bundle.discTotal = readPartTotalByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyDiscNumber,
            keySpace: .iTunes
        ) ?? readPartTotal(from: allItems, identifiers: [.id3MetadataPartOfASet])

        bundle.bpm = readIntByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyBeatsPerMin,
            keySpace: .iTunes
        ) ?? readInt(from: allItems, identifiers: [
            .id3MetadataBeatsPerMinute          // TBPM
        ])

        bundle.comment = readComment(from: allItems)

        let (rgTrack, rgAlbum) = readReplayGain(from: allItems)
        bundle.replayGainTrack = rgTrack
        bundle.replayGainAlbum = rgAlbum

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

    /// Returns the first non-empty string matching any of the given identifiers.
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

    /// Parses the N component of a "N/total" string from the first matching identifier.
    ///
    /// Examples: "3/12" → 3, "3" → 3. Returns nil if N ≤ 0.
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

    /// Variant of `readPartNumber` using key+keySpace lookup.
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

    /// Parses the total component of a "N/total" string from the first matching identifier.
    ///
    /// Examples: "3/12" → 12, "3" → nil. Returns nil if total ≤ 0.
    private func readPartTotal(
        from items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) -> Int? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first) {
                if let n = parseTotalNumber(from: s) { return n }
            }
        }
        return nil
    }

    /// Variant of `readPartTotal` using key+keySpace lookup.
    private func readPartTotalByKey(
        from items: [AVMetadataItem],
        key: AVMetadataKey,
        keySpace: AVMetadataKeySpace
    ) -> Int? {
        let matches = AVMetadataItem.metadataItems(from: items,
                                                   withKey: key,
                                                   keySpace: keySpace)
        if let first = matches.first,
           let s = loadString(from: first) {
            return parseTotalNumber(from: s)
        }
        return nil
    }

    /// Parses an integer from a numeric metadata tag (BPM, etc.) via identifier.
    private func readInt(
        from items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) -> Int? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first) {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if let d = Double(trimmed), d > 0 { return Int(d) }
            }
        }
        return nil
    }

    /// Parses an integer from a numeric metadata tag via key+keySpace lookup.
    ///
    /// Required for iTunes fields that have an `AVMetadataKey` constant but no
    /// corresponding named `AVMetadataIdentifier` constant (e.g. BPM / tempo).
    private func readIntByKey(
        from items: [AVMetadataItem],
        key: AVMetadataKey,
        keySpace: AVMetadataKeySpace
    ) -> Int? {
        let matches = AVMetadataItem.metadataItems(from: items,
                                                   withKey: key,
                                                   keySpace: keySpace)
        if let first = matches.first,
           let s = loadString(from: first) {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let d = Double(trimmed), d > 0 { return Int(d) }
        }
        return nil
    }

    /// Reads the comment field from iTunes or ID3 comment frames.
    ///
    /// iTunes: .iTunesMetadataUserComment (plain string)
    /// ID3 COMM: value may include a language prefix like "eng\0\0Actual comment".
    /// We strip the prefix and return only the meaningful text.
    private func readComment(from items: [AVMetadataItem]) -> String? {
        // Try iTunes first (clean string, no prefix)
        if let s = readString(from: items, identifiers: [.iTunesMetadataUserComment]),
           !s.isEmpty {
            return s
        }
        // Try ID3 COMM
        let commItems = AVMetadataItem.metadataItems(from: items,
                                                     filteredByIdentifier: .id3MetadataComments)
        for item in commItems {
            guard let raw = loadString(from: item), !raw.isEmpty else { continue }
            // COMM format: "eng\0short desc\0actual text" — split on null bytes
            let parts = raw.components(separatedBy: "\0").filter { !$0.isEmpty }
            // Return the last non-trivial component (the actual comment text)
            if let last = parts.last(where: { $0.count > 3 && !$0.hasPrefix("eng") }),
               !last.isEmpty {
                return last
            }
            if let last = parts.last, !last.isEmpty, last.count > 3 { return last }
        }
        return nil
    }

    /// Reads ReplayGain track and album gain values from ID3 TXXX frames.
    ///
    /// ReplayGain is stored as TXXX (user-defined text) with description keys:
    ///   "replaygain_track_gain" / "replaygain_album_gain"
    /// Value format: "-5.32 dB"
    ///
    /// Returns (trackGain, albumGain); either may be nil if not present.
    private func readReplayGain(from items: [AVMetadataItem]) -> (Double?, Double?) {
        let txxxItems = AVMetadataItem.metadataItems(from: items,
                                                     filteredByIdentifier: .id3MetadataUserText)
        var trackGain: Double?
        var albumGain: Double?

        for item in txxxItems {
            // Load extraAttributes asynchronously (extraAttributes property deprecated macOS 13+)
            let sema = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var extras: [AVMetadataExtraAttributeKey: Any]?
            Task { @Sendable in
                extras = try? await item.load(.extraAttributes)
                sema.signal()
            }
            sema.wait()

            guard
                let extras,
                let desc = extras[AVMetadataExtraAttributeKey("info")] as? String
            else { continue }

            let key = desc.lowercased().trimmingCharacters(in: .whitespaces)
            guard key == "replaygain_track_gain" || key == "replaygain_album_gain"
            else { continue }

            guard let raw = loadString(from: item) else { continue }
            // Parse "-5.32 dB" → -5.32
            let numStr = raw
                .replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            guard let value = Double(numStr) else { continue }

            if key == "replaygain_track_gain" { trackGain = value }
            else { albumGain = value }
        }
        return (trackGain, albumGain)
    }

    /// Parses a year integer from release-date / year metadata identifiers.
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

    /// Parses the N component of a "N/total" string.
    /// Examples: "3/12" → 3, "3" → 3. Returns nil if N ≤ 0.
    private func parsePartNumber(from s: String) -> Int? {
        let part = s.split(separator: "/").first.map(String.init) ?? s
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n > 0 { return n }
        return nil
    }

    /// Parses the total component of a "N/total" string.
    /// Examples: "3/12" → 12, "3" → nil. Returns nil if total ≤ 0.
    private func parseTotalNumber(from s: String) -> Int? {
        let parts = s.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let trimmed = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n > 0 { return n }
        return nil
    }
}
