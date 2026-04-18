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
//  After tag extraction, a fourth step reads technical audio info
//  (codec, encoding, duration, bitrate, sampleRate, channels, fileSize)
//  from the same AVURLAsset. These are NOT tag metadata but are included
//  in TagBundle so that consumers do not need to open the asset a second
//  time. `encoding` is derived from `codec`.
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
            .iTunesMetadataComposer,            // ©wrt
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
            .id3MetadataTrackNumber             // TRCK  e.g. "3/12"
        ])

        // discNumber: AVMetadataIdentifier has no named constant for iTunes disc number.
        // Use the key+keySpace API with the known AVMetadataKey constant instead.
        bundle.discNumber = readPartNumberByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyDiscNumber,
            keySpace: .iTunes
        )
        // Also parse from ID3 TPOS frame ("N/total" format).
        if bundle.discNumber == nil {
            bundle.discNumber = readPartNumber(from: allItems, identifiers: [
                .id3MetadataPartOfASet           // TPOS
            ])
        }

        bundle.discTotal = readPartTotalByKey(
            from: allItems,
            key: AVMetadataKey.iTunesMetadataKeyDiscNumber,
            keySpace: .iTunes
        )
        if bundle.discTotal == nil {
            bundle.discTotal = readPartTotal(from: allItems, identifiers: [
                .id3MetadataPartOfASet           // TPOS  e.g. "1/2"
            ])
        }

        bundle.bpm = readInt(from: allItems, identifiers: [
            .id3MetadataBeatsPerMinute          // TBPM
        ])
        if bundle.bpm == nil {
            bundle.bpm = readIntByKey(
                from: allItems,
                key: AVMetadataKey.iTunesMetadataKeyBeatsPerMin,
                keySpace: .iTunes
            )
        }

        bundle.comment = readString(from: allItems, identifiers: [
            .id3MetadataComments                // COMM
        ])
        if bundle.comment == nil {
            bundle.comment = readStringByKey(
                from: allItems,
                key: AVMetadataKey.iTunesMetadataKeyUserComment,
                keySpace: .iTunes
            )
        }

        let (rgTrack, rgAlbum) = readReplayGain(from: allItems)
        bundle.replayGainTrack = rgTrack
        bundle.replayGainAlbum = rgAlbum

        // ── Step 4: Technical info (duration, bitrate, sampleRate, channels, fileSize) ──
        //
        // These are read from the same AVURLAsset that is already open for
        // tag extraction. Including them in TagBundle avoids a second asset
        // load in the consumer layer.
        // Non-fatal: any failure leaves the corresponding field nil.

        nonisolated(unsafe) var durationSeconds: TimeInterval?
        nonisolated(unsafe) var bitrateKbps: Int?
        nonisolated(unsafe) var sampleRateHz: Double?
        nonisolated(unsafe) var channelCount: Int?
        nonisolated(unsafe) var codecName: String?

        let sema4 = DispatchSemaphore(value: 0)
        Task { @Sendable in
            // Duration
            if let cmDuration = try? await asset.load(.duration) {
                let s = cmDuration.seconds
                if s > 0 && !s.isNaN && !s.isInfinite {
                    durationSeconds = s
                }
            }

            // Audio track properties: bitrate, sampleRate, channels, codec
            if let assetTracks = try? await asset.load(.tracks),
               let firstAudio = assetTracks.first(where: { $0.mediaType == .audio }) {

                if let rate = try? await firstAudio.load(.estimatedDataRate), rate > 0 {
                    let kbps = Int(rate / 1000)
                    if kbps > 0 { bitrateKbps = kbps }
                }

                if let formatDescriptions = try? await firstAudio.load(.formatDescriptions),
                   let firstDesc = formatDescriptions.first {
                    let desc = firstDesc as CMFormatDescription
                    if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                        let sr = basic.pointee.mSampleRate
                        if sr > 0 { sampleRateHz = sr }
                        let ch = Int(basic.pointee.mChannelsPerFrame)
                        if ch > 0 { channelCount = ch }
                        codecName = Self.codecName(for: basic.pointee)
                    }
                }
            }

            sema4.signal()
        }
        sema4.wait()

        bundle.duration = durationSeconds
        bundle.bitrate = bitrateKbps
        bundle.sampleRate = sampleRateHz
        bundle.channels = channelCount
        bundle.codec = codecName
        bundle.encoding = codecName.flatMap(Self.encodingClassification(for:))

        // fileSize: synchronous FileManager call, no async needed.
        if url.isFileURL {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            bundle.fileSize = attrs?[.size] as? Int
        }

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

    // MARK: - New helpers for extended fields

    /// Parses the total (second) part of an "N/total" track or disc number string.
    ///
    /// Example: `"3/12"` → `12`, `"3"` → `nil`.
    /// Returns `nil` if no total part exists or the parsed value is 0 or negative.
    private func readPartTotal(
        from items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier]
    ) -> Int? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items,
                                                       filteredByIdentifier: identifier)
            if let first = matches.first,
               let s = loadString(from: first) {
                if let n = parsePartTotal(from: s) { return n }
            }
        }
        return nil
    }

    /// Key+keySpace variant of `readPartTotal`.
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
            return parsePartTotal(from: s)
        }
        return nil
    }

    /// Parses "N/total" into the total component.
    /// Returns `nil` if no "/" separator or total is 0 or negative.
    private func parsePartTotal(from s: String) -> Int? {
        let parts = s.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let trimmed = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed), n > 0 { return n }
        return nil
    }

    /// Reads an integer value from the first matching identifier.
    ///
    /// Parses the string representation of the metadata value.
    /// Returns `nil` if no match or the value cannot be converted to a positive Int.
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
                if let n = Int(trimmed), n > 0 { return n }
            }
        }
        return nil
    }

    /// Key+keySpace variant of `readInt`.
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
            if let n = Int(trimmed), n > 0 { return n }
        }
        return nil
    }

    /// Key+keySpace variant of `readString` for iTunes fields without a named identifier.
    private func readStringByKey(
        from items: [AVMetadataItem],
        key: AVMetadataKey,
        keySpace: AVMetadataKeySpace
    ) -> String? {
        let matches = AVMetadataItem.metadataItems(from: items,
                                                   withKey: key,
                                                   keySpace: keySpace)
        if let first = matches.first,
           let s = loadString(from: first),
           !s.isEmpty {
            return s
        }
        return nil
    }

    /// Reads ReplayGain track and album gain values from ID3 TXXX frames.
    ///
    /// ReplayGain values are stored as user-defined text frames (TXXX) with
    /// descriptions "REPLAYGAIN_TRACK_GAIN" and "REPLAYGAIN_ALBUM_GAIN".
    /// Values are strings like "-3.21 dB" or "+1.50 dB"; the numeric part is parsed.
    /// Returns a tuple of (trackGain, albumGain), each `nil` if not present.
    private func readReplayGain(
        from items: [AVMetadataItem]
    ) -> (track: Double?, album: Double?) {
        var trackGain: Double? = nil
        var albumGain: Double? = nil

        let txxx = AVMetadataItem.metadataItems(from: items,
                                                filteredByIdentifier: .id3MetadataUserText)
        for item in txxx {
            // extraAttributes is deprecated in macOS 13 but remains functional.
            // load(.extraAttributes) is the replacement; both work at runtime.
            // swiftlint:disable:next legacy_objc_type
            guard let info = item.extraAttributes?[.info] as? String else { continue }
            guard let valueStr = loadString(from: item) else { continue }

            let key = info.trimmingCharacters(in: .whitespaces).uppercased()
            // Value format: "-3.21 dB" or "+1.50 dB" — take the numeric token only.
            let numeric = valueStr
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ")
                .first
                .map(String.init) ?? valueStr

            switch key {
            case "REPLAYGAIN_TRACK_GAIN":
                trackGain = Double(numeric)
            case "REPLAYGAIN_ALBUM_GAIN":
                albumGain = Double(numeric)
            default:
                break
            }
        }
        return (trackGain, albumGain)
    }

    // MARK: - Codec / Encoding Mapping

    /// Maps a CoreAudio `AudioStreamBasicDescription` to a human-readable
    /// codec name in foobar2000-style.
    ///
    /// Scope is limited to the codecs HarmoniaPlayer supports:
    /// - v0.1 Free: MP3, AAC LC, Apple Lossless (ALAC), PCM (WAV / AIFF)
    /// - v0.2 Pro: FLAC
    ///
    /// DSD (`.dsf` / `.dff`) is not handled here — it is decoded via a
    /// separate adapter chain in v0.2 Pro and does not flow through
    /// AVFoundation's `AudioStreamBasicDescription`.
    ///
    /// Returns `nil` for codec IDs that are not recognised.
    fileprivate static func codecName(for asbd: AudioStreamBasicDescription) -> String? {
        switch asbd.mFormatID {
        case kAudioFormatMPEGLayer3:
            return "MP3 Layer 3"
        case kAudioFormatMPEG4AAC:
            return "AAC LC"
        case kAudioFormatAppleLossless:
            return "Apple Lossless (ALAC)"
        case kAudioFormatLinearPCM:
            return "PCM"
        case kAudioFormatFLAC:
            return "FLAC"
        default:
            return nil
        }
    }

    /// Classifies a codec name as `"lossy"` or `"lossless"`.
    /// Returns `nil` for codec strings that are not recognised.
    fileprivate static func encodingClassification(for codec: String) -> String? {
        let lossy: Set<String> = [
            "MP3 Layer 3",
            "AAC LC"
        ]
        let lossless: Set<String> = [
            "Apple Lossless (ALAC)",
            "PCM",
            "FLAC"
        ]
        if lossy.contains(codec) { return "lossy" }
        if lossless.contains(codec) { return "lossless" }
        return nil
    }
}
