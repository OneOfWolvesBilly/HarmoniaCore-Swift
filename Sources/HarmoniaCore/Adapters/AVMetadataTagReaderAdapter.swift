//
//  AVMetadataTagReaderAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Swift 6 compatible using @preconcurrency.
//  Supports macOS 13+ / iOS 16+
//

import Foundation
@preconcurrency import AVFoundation

public final class AVMetadataTagReaderAdapter: TagReaderPort {

    public init() {}

    public func read(url: URL) throws -> TagBundle {
        let asset = AVAsset(url: url)
        
        // Load metadata
        let semaphore = DispatchSemaphore(value: 0)
        var loadedMetadata: [AVMetadataItem] = []
        var loadError: Error?
        
        Task {
            do {
                loadedMetadata = try await asset.load(.commonMetadata)
            } catch {
                loadError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = loadError {
            throw CoreError.ioError(underlying: error)
        }
        
        var bundle = TagBundle()
        
        // Helper function to load string value
        func loadStringValue(from item: AVMetadataItem) -> String? {
            let semaphore = DispatchSemaphore(value: 0)
            var result: String?
            
            Task {
                result = try? await item.load(.stringValue)
                semaphore.signal()
            }
            
            semaphore.wait()
            return result
        }
        
        // Extract common metadata fields
        for item in loadedMetadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                bundle.title = loadStringValue(from: item)
            case .commonKeyArtist:
                bundle.artist = loadStringValue(from: item)
            case .commonKeyAlbumName:
                bundle.album = loadStringValue(from: item)
            default:
                break
            }
        }
        
        // Extract artwork if available
        if let artworkItem = AVMetadataItem.metadataItems(
            from: loadedMetadata,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first {
            let semaphore = DispatchSemaphore(value: 0)
            var artworkData: Data?
            
            Task {
                artworkData = try? await artworkItem.load(.dataValue)
                semaphore.signal()
            }
            
            semaphore.wait()
            bundle.artworkData = artworkData
        }
        
        return bundle
    }
}
