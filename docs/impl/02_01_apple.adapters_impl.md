# Apple Adapters Implementation (Swift)

This document describes Swift implementations of adapters for the Apple platform.

**Spec Reference:** [`specs/02_01_apple.adapters.md`](../specs/02_01_apple.adapters.md)

---

## OSLogAdapter : LoggerPort

Uses `os.Logger` for unified logging.

```swift
import OSLog

public final class OSLogAdapter: LoggerPort {
    private let logger: Logger
    
    public init(subsystem: String = "com.harmonia.core", 
                category: String = "default") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    
    public func debug(_ msg: @autoclosure () -> String) {
        logger.debug("\(msg())")
    }
    
    public func info(_ msg: @autoclosure () -> String) {
        logger.info("\(msg())")
    }
    
    public func warn(_ msg: @autoclosure () -> String) {
        logger.warning("\(msg())")
    }
    
    public func error(_ msg: @autoclosure () -> String) {
        logger.error("\(msg())")
    }
}
```

**Thread Safety:** `os.Logger` is thread-safe by default.

---

## NoopLogger : LoggerPort

Zero-overhead no-op implementation for testing.

```swift
public final class NoopLogger: LoggerPort {
    public init() {}
    
    public func debug(_ msg: @autoclosure () -> String) {}
    public func info(_ msg: @autoclosure () -> String) {}
    public func warn(_ msg: @autoclosure () -> String) {}
    public func error(_ msg: @autoclosure () -> String) {}
}
```

---

## MonotonicClockAdapter : ClockPort

Uses `DispatchTime` for nanosecond precision monotonic time.

```swift
import Dispatch

public final class MonotonicClockAdapter: ClockPort {
    public init() {}
    
    public func now() -> UInt64 {
        return DispatchTime.now().uptimeNanoseconds
    }
}
```

**Precision:** Nanosecond resolution guaranteed.

---

## SandboxFileAccessAdapter : FileAccessPort

Wraps `FileHandle` with UUID-based tokens for sandbox-safe file access.

```swift
import Foundation

public final class SandboxFileAccessAdapter: FileAccessPort {
    private var handles: [FileHandleToken: FileHandle] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func open(url: URL) throws -> FileHandleToken {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let token = FileHandleToken(id: UUID())
            lock.withLock {
                handles[token] = handle
            }
            return token
        } catch {
            throw mapToCorError(error, context: "Opening file: \(url.path)")
        }
    }
    
    public func read(_ token: FileHandleToken, 
                     into buffer: UnsafeMutableRawPointer, 
                     count: Int) throws -> Int {
        guard let handle = lock.withLock({ handles[token] }) else {
            throw CoreError.invalidState("File handle not found")
        }
        
        do {
            let data = try handle.read(upToCount: count) ?? Data()
            let bytesToCopy = min(data.count, count)
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), 
                          count: bytesToCopy)
            return bytesToCopy
        } catch {
            throw mapToCoreError(error, context: "Reading file")
        }
    }
    
    public func size(_ token: FileHandleToken) throws -> Int64 {
        guard let handle = lock.withLock({ handles[token] }) else {
            throw CoreError.invalidState("File handle not found")
        }
        
        do {
            let current = try handle.offset()
            try handle.seekToEnd()
            let size = try handle.offset()
            try handle.seek(toOffset: current)
            return Int64(size)
        } catch {
            throw mapToCoreError(error, context: "Getting file size")
        }
    }
    
    public func close(_ token: FileHandleToken) {
        lock.withLock {
            handles.removeValue(forKey: token)
        }
    }
    
    private func mapToCoreError(_ error: Error, context: String) -> CoreError {
        if let nsError = error as NSError? {
            switch nsError.code {
            case NSFileReadNoSuchFileError:
                return .notFound("\(context): File not found")
            case NSFileReadNoPermissionError:
                return .ioError(underlying: error)
            default:
                return .ioError(underlying: error)
            }
        }
        return .ioError(underlying: error)
    }
}
```

**Thread Safety:** Internal locking ensures thread-safe access to file handles.

---

## AVAssetReaderDecoderAdapter : DecoderPort

Uses `AVAssetReader` to decode audio files to interleaved Float32 PCM.

**Note:** Full implementation requires significant AVFoundation integration code.  
See actual source code for complete implementation.

**Key Points:**
- Supports: MP3, AAC, ALAC, WAV, AIFF, CAF
- Output: Interleaved Float32 PCM in range [-1.0, 1.0]
- Thread-safe: Safe to use on background threads

---

## AVAudioEngineOutputAdapter : AudioOutputPort

Uses `AVAudioEngine` and `AVAudioPlayerNode` for audio playback.

**Typical Usage:**
```swift
@MainActor
public final class AVAudioEngineOutputAdapter: AudioOutputPort {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    public func configure(sampleRate: Double, channels: Int, framesPerBuffer: Int) {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }
    
    public func start() throws {
        try engine.start()
        playerNode.play()
    }
    
    public func stop() {
        playerNode.stop()
        engine.stop()
    }
    
    public func render(_ buffer: UnsafePointer<Float>, frameCount: Int) throws -> Int {
        // Schedule buffer to playerNode
        // Implementation details in actual code
        return frameCount
    }
}
```

**Thread Safety:** Must be called on `@MainActor` for UI integration.

---

## AVMetadataTagReaderAdapter : TagReaderPort

Reads metadata using `AVAsset` APIs.

```swift
import AVFoundation

public final class AVMetadataTagReaderAdapter: TagReaderPort {
    public init() {}
    
    public func read(url: URL) throws -> TagBundle {
        let asset = AVAsset(url: url)
        var bundle = TagBundle()
        
        for item in asset.commonMetadata {
            switch item.commonKey {
            case .commonKeyTitle:
                bundle.title = item.stringValue
            case .commonKeyArtist:
                bundle.artist = item.stringValue
            case .commonKeyAlbumName:
                bundle.album = item.stringValue
            case .commonKeyType:
                bundle.genre = item.stringValue
            default:
                break
            }
        }
        
        // Extract artwork if available
        if let artworkItem = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first {
            bundle.artworkData = artworkItem.dataValue
        }
        
        return bundle
    }
}
```

---

## AVMutableTagWriterAdapter : TagWriterPort

Currently not functional on any Apple platform.

```swift
public final class AVMutableTagWriterAdapter: TagWriterPort {
    public init() {}
    
    public func write(url: URL, tags: TagBundle) throws {
        throw CoreError.unsupported(
            "Tag writing is not supported. " +
            "iOS: sandbox restrictions. macOS: deferred."
        )
    }
}
```

**Rationale:**
- iOS: Sandbox restrictions prevent file writes
- macOS: Support deferred to future version

---

## Error Mapping

All AVFoundation errors must be mapped to `CoreError`:

```swift
private func mapAVError(_ error: Error) -> CoreError {
    if let avError = error as? AVError {
        switch avError.code {
        case .fileNotFound:
            return .notFound("File not found: \(avError.localizedDescription)")
        case .unsupportedOutputSettings, .decoderNotFound:
            return .unsupported(avError.localizedDescription)
        case .decodeFailed:
            return .decodeError(avError.localizedDescription)
        default:
            return .ioError(underlying: error)
        }
    }
    return .ioError(underlying: error)
}
```

---

## Implementation Checklist

When implementing Apple adapters:

- [ ] Use `Sendable` for thread-safe types
- [ ] Use `@MainActor` for UI-bound components (audio engine)
- [ ] Map all platform errors to `CoreError`
- [ ] Implement proper resource cleanup in `deinit`
- [ ] Add comprehensive error messages for debugging
- [ ] Test on both iOS and macOS