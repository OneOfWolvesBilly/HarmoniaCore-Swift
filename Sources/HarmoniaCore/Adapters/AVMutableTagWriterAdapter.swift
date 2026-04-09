//
//  AVMutableTagWriterAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Swift 6 compatible using @preconcurrency.
//  Supports macOS 13+ / iOS 16+
//

import Foundation
@preconcurrency import AVFoundation

public final class AVMutableTagWriterAdapter: TagWriterPort {
    public init() {}

    /// Builds AVMutableMetadataItem array from TagBundle.
    /// Internal for testing. Called by write() internally.
    /// replayGainTrack and replayGainAlbum are intentionally excluded.
    func buildMetadataItems(from tags: TagBundle) -> [AVMutableMetadataItem] {
        var items: [AVMutableMetadataItem] = []

        if let title = tags.title {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            items.append(item)
        }

        if let artist = tags.artist {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierArtist
            item.value = artist as NSString
            items.append(item)
        }

        if let album = tags.album {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierAlbumName
            item.value = album as NSString
            items.append(item)
        }

        if let albumArtist = tags.albumArtist {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataBand                  // TPE2
            item.value = albumArtist as NSString
            items.append(item)
        }

        if let composer = tags.composer {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataComposer              // TCOM
            item.value = composer as NSString
            items.append(item)
        }

        if let genre = tags.genre {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataContentType           // TCON
            item.value = genre as NSString
            items.append(item)
        }

        if let year = tags.year {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataRecordingTime         // TDRC
            item.value = "\(year)" as NSString
            items.append(item)
        }

        if let trackNumber = tags.trackNumber {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataTrackNumber           // TRCK
            let value: String
            if let trackTotal = tags.trackTotal {
                value = "\(trackNumber)/\(trackTotal)"
            } else {
                value = "\(trackNumber)"
            }
            item.value = value as NSString
            items.append(item)
        }

        if let discNumber = tags.discNumber {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataPartOfASet            // TPOS
            let value: String
            if let discTotal = tags.discTotal {
                value = "\(discNumber)/\(discTotal)"
            } else {
                value = "\(discNumber)"
            }
            item.value = value as NSString
            items.append(item)
        }

        if let bpm = tags.bpm {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataBeatsPerMinute        // TBPM
            item.value = "\(bpm)" as NSString
            items.append(item)
        }

        if let comment = tags.comment {
            let item = AVMutableMetadataItem()
            item.identifier = .id3MetadataComments              // COMM
            item.value = comment as NSString
            items.append(item)
        }

        if let artworkData = tags.artworkData {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierArtwork
            item.value = artworkData as NSData
            items.append(item)
        }

        // replayGainTrack and replayGainAlbum are intentionally excluded.
        // AVFoundation cannot write TXXX frames.
        // Writing support deferred to future TagLib-based adapter.

        return items
    }

    public func write(url: URL, tags: TagBundle) throws {
        #if os(iOS)
        // iOS sandbox restrictions prevent file writes in most cases
        throw CoreError.unsupported(
            "Tag writing is not supported on iOS due to sandbox restrictions. " +
            "Use TagLibTagWriterAdapter on macOS if needed."
        )
        #else
        // Check for unsupported formats before any file I/O.
        // AVFoundation export does not support FLAC, DSF, or DFF.
        let ext = url.pathExtension.lowercased()
        if ["flac", "dsf", "dff"].contains(ext) {
            throw CoreError.unsupported(
                "Tag writing is not supported for .\(ext) format. " +
                "Use TagLibTagWriterAdapter for FLAC/DSF/DFF support."
            )
        }

        // macOS implementation
        
        // Load the asset
        let asset = AVURLAsset(url: url)
        
        // Check if the asset is writable
        let semaphore1 = DispatchSemaphore(value: 0)
        var isExportable = false
        
        Task {
            do {
                isExportable = try await asset.load(.isExportable)
            } catch {
                isExportable = false
            }
            semaphore1.signal()
        }
        
        semaphore1.wait()
        
        guard isExportable else {
            throw CoreError.unsupported("Asset format does not support tag writing")
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw CoreError.unsupported("Cannot create export session for this asset")
        }
        
        // Build metadata items from TagBundle
        let metadataItems = buildMetadataItems(from: tags)

        // Set metadata
        exportSession.metadata = metadataItems
        
        // Create temporary output URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = AVFileType(rawValue: url.pathExtension)
        
        // Export synchronously
        // Use nonisolated(unsafe) to bypass Sendable checking for AVFoundation types
        nonisolated(unsafe) let session = exportSession
        
        let semaphore2 = DispatchSemaphore(value: 0)
        var exportError: Error?
        
        session.exportAsynchronously {
            if session.status == .failed {
                exportError = session.error ?? NSError(
                    domain: "AVMutableTagWriterAdapter",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed"]
                )
            }
            semaphore2.signal()
        }
        
        semaphore2.wait()
        
        if let error = exportError {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            throw CoreError.ioError(underlying: error)
        }
        
        guard session.status == .completed else {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            throw CoreError.ioError(underlying: NSError(
                domain: "AVMutableTagWriterAdapter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Export did not complete: \(session.status.rawValue)"]
            ))
        }
        
        // Replace original file with temp file
        do {
            // Remove original
            try FileManager.default.removeItem(at: url)
            
            // Move temp to original location
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            throw CoreError.ioError(underlying: error)
        }
        #endif
    }
}
