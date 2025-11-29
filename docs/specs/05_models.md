# 05. Models Specification

This document defines the platform-neutral data models used throughout HarmoniaCore.
These models cross Port boundaries and must be representable in both Swift and C++20.

All content in this specification is written in English and is language-neutral.
Code samples are illustrative only; actual implementations MUST preserve the semantics
defined here while using idiomatic constructs for their target language.

---

## Design Principles

1. **Platform Independence**  
   Models MUST NOT reference platform-specific types (e.g., `NSError`, `AVAudioFormat`).

2. **Immutability Preferred**  
   Models SHOULD be immutable where possible to ensure thread safety.

3. **Simple Data Structures**  
   Models are pure data - no business logic, no methods beyond basic accessors.

4. **Optional Fields**  
   Use optional/nullable types for fields that may not always be present.

---

## StreamInfo

Describes an audio stream's format and duration.

### Fields

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `duration` | `Double` | Duration in seconds | `≥ 0.0`, may be `INFINITY` for streams |
| `sampleRate` | `Double` | Sample rate in Hz | Common: 44100.0, 48000.0, 88200.0, 96000.0, 192000.0 |
| `channels` | `Int` | Number of audio channels | `≥ 1`, typically 1 (mono) or 2 (stereo) |
| `bitDepth` | `Int` | Bit depth per sample | Common: 16, 24, 32 (for PCM formats) |

### Semantics

- **duration:**  
  Total playable duration. For finite files, this is exact. For streams, may be `INFINITY`.

- **sampleRate:**  
  Native sample rate of the audio. Decoders MUST output at this rate (no resampling at decode stage).

- **channels:**  
  Channel count. Decoders output interleaved PCM with this many channels.

- **bitDepth:**  
  Original bit depth. For compressed formats, this represents the target PCM bit depth.  
  Note: HarmoniaCore always uses Float32 internally, so this is informational.

### Illustrative Shapes

**Swift:**
```swift
public struct StreamInfo: Sendable, Equatable {
    public let duration: Double
    public let sampleRate: Double
    public let channels: Int
    public let bitDepth: Int
    
    public init(duration: Double, sampleRate: Double, channels: Int, bitDepth: Int) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}
```

**C++:**
```cpp
struct StreamInfo {
    double duration;
    double sample_rate;
    int channels;
    int bit_depth;
    
    bool operator==(const StreamInfo&) const = default;
};
```

---

## TagBundle

Contains metadata tags extracted from or to be written to an audio file.

### Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `title` | `String?` | Track title | "Bohemian Rhapsody" |
| `artist` | `String?` | Primary artist | "Queen" |
| `album` | `String?` | Album name | "A Night at the Opera" |
| `albumArtist` | `String?` | Album artist (may differ from artist) | "Queen" |
| `genre` | `String?` | Musical genre | "Rock" |
| `year` | `Int?` | Release year | 1975 |
| `trackNumber` | `Int?` | Track number on album | 11 |
| `discNumber` | `Int?` | Disc number in multi-disc set | 1 |
| `artworkData` | `Data?` / `ByteArray?` | Embedded cover art (raw image bytes) | JPEG/PNG data |

### Semantics

- **Optional Fields:**  
  All fields are optional. `nil`/`null`/empty indicates the field is not present in the source file.

- **String Encoding:**  
  All strings MUST be UTF-8 encoded.

- **artworkData:**  
  Raw image bytes (typically JPEG or PNG). Implementations SHOULD detect image format from magic bytes.  
  Size limit: Recommended ≤ 10 MB per file format specifications.

### Cross-Platform Consistency

- Tag names MUST map consistently across platforms:
  - ID3v2 `TIT2` → `title`
  - ID3v2 `TPE1` → `artist`
  - Vorbis `TITLE` → `title`
  - Vorbis `ARTIST` → `artist`
  - MP4 `©nam` → `title`
  - MP4 `©ART` → `artist`

- Missing tags MUST result in `nil`/`null` fields, NOT empty strings.

### Illustrative Shapes

**Swift:**
```swift
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
    
    public init() {}
}
```

**C++:**
```cpp
struct TagBundle {
    std::optional<std::string> title;
    std::optional<std::string> artist;
    std::optional<std::string> album;
    std::optional<std::string> album_artist;
    std::optional<std::string> genre;
    std::optional<int> year;
    std::optional<int> track_number;
    std::optional<int> disc_number;
    std::optional<std::vector<uint8_t>> artwork_data;
    
    bool operator==(const TagBundle&) const = default;
};
```

---

## CoreError

Unified error enumeration for all recoverable errors in HarmoniaCore.

### Categories

| Category | Description | When to Use |
|----------|-------------|-------------|
| `invalidArgument(String)` | Invalid parameter value | Null/empty URL, negative seek position, invalid buffer size |
| `invalidState(String)` | Operation invalid in current state | Play with no track loaded, configure while playing |
| `notFound(String)` | Resource not found | File does not exist, invalid file path |
| `ioError(underlying?)` | I/O operation failed | Permission denied, disk read error, network failure |
| `decodeError(String)` | Audio decode failed | Corrupted file, unsupported codec variant |
| `unsupported(String)` | Feature/format not supported | FLAC on standard build, DSD without Pro license, write on iOS |

### Semantics

- **invalidArgument:**  
  User provided invalid input. Should include parameter name and reason.  
  Example: `"Invalid seek position: -5.0 (must be ≥ 0)"`

- **invalidState:**  
  Operation is valid but not allowed in current state. Should describe expected state.  
  Example: `"Cannot play: no track loaded. Call load() first."`

- **notFound:**  
  Requested resource does not exist. Should include resource identifier.  
  Example: `"File not found: /path/to/track.mp3"`

- **ioError:**  
  Low-level I/O operation failed. MAY wrap underlying platform error for debugging.  
  Example (Swift): `CoreError.ioError(underlying: posixError)`  
  Example (C++): `CoreError::IoError("Read failed: " + std::strerror(errno))`

- **decodeError:**  
  Audio decoding failed. Should include position/frame if available.  
  Example: `"Decode failed at frame 12345: invalid MPEG sync word"`

- **unsupported:**  
  Feature or format is not available on this platform/build.  
  Example: `"FLAC decoding not supported in standard builds. Use macOS Pro."`

### Error Recovery

- All `CoreError` values are **recoverable** - they should not crash the application.
- Services SHOULD transition to `error` state and allow recovery via `load()` or other operations.
- Unrecoverable errors (e.g., out-of-memory, programming errors) should use platform-native mechanisms (assertions, exceptions).

### Illustrative Shapes

**Swift:**
```swift
public enum CoreError: Error, Sendable {
    case invalidArgument(String)
    case invalidState(String)
    case notFound(String)
    case ioError(underlying: Error)
    case decodeError(String)
    case unsupported(String)
}
```

**C++:**
```cpp
enum class CoreErrorType {
    InvalidArgument,
    InvalidState,
    NotFound,
    IoError,
    DecodeError,
    Unsupported
};

class CoreError : public std::exception {
private:
    CoreErrorType type_;
    std::string message_;
    
public:
    CoreError(CoreErrorType type, std::string message)
        : type_(type), message_(std::move(message)) {}
    
    CoreErrorType type() const { return type_; }
    const char* what() const noexcept override { return message_.c_str(); }
    
    // Factory methods
    static CoreError InvalidArgument(std::string msg) {
        return CoreError(CoreErrorType::InvalidArgument, std::move(msg));
    }
    
    static CoreError InvalidState(std::string msg) {
        return CoreError(CoreErrorType::InvalidState, std::move(msg));
    }
    
    static CoreError NotFound(std::string msg) {
        return CoreError(CoreErrorType::NotFound, std::move(msg));
    }
    
    static CoreError IoError(std::string msg) {
        return CoreError(CoreErrorType::IoError, std::move(msg));
    }
    
    static CoreError DecodeError(std::string msg) {
        return CoreError(CoreErrorType::DecodeError, std::move(msg));
    }
    
    static CoreError Unsupported(std::string msg) {
        return CoreError(CoreErrorType::Unsupported, std::move(msg));
    }
};
```

### Error Mapping Guidelines

See `01_architecture.md` for comprehensive error mapping rules.

**Quick Reference:**

| Platform Error | CoreError | Example |
|----------------|-----------|---------|
| POSIX `ENOENT` | `notFound` | File not found |
| POSIX `EACCES` | `ioError` | Permission denied |
| AVFoundation `fileNotFound` | `notFound` | File not found |
| AVFoundation `decoderNotFound` | `unsupported` | Codec not available |
| FFmpeg `AVERROR_INVALIDDATA` | `decodeError` | Corrupted stream |

---

## Additional Types

### FileHandleToken (Opaque)

Used by `FileAccessPort` to track open file handles.

**Requirements:**
- MUST be hashable/comparable for use in collections.
- MUST be unique per open file operation.
- Implementation-defined structure (e.g., UUID, integer handle, pointer).

**Swift:**
```swift
public struct FileHandleToken: Hashable, Sendable {
    let id: UUID
    public init(id: UUID) { self.id = id }
}
```

**C++:**
```cpp
struct FileHandleToken {
    std::string id; // or int, or void*, implementation-defined
    
    bool operator==(const FileHandleToken&) const = default;
};

// Specialization for std::hash if needed
template<>
struct std::hash<FileHandleToken> {
    size_t operator()(const FileHandleToken& token) const {
        return std::hash<std::string>{}(token.id);
    }
};
```

### DecodeHandle (Opaque)

Used by `DecoderPort` to track open decode sessions.

**Requirements:**
- Similar to `FileHandleToken` - opaque, unique, hashable.
- Implementation may wrap native decoder handles (e.g., `AVAssetReader*`, `AVFormatContext*`).

---

## Thread Safety Considerations

### Immutable Models
- `StreamInfo` is immutable → naturally thread-safe.
- `TagBundle` fields are independent → safe to read concurrently if not mutated.

### Mutable Models
- `TagBundle` when used for writing → caller must synchronize.
- Services that hold mutable models → must provide synchronization.

### Error Handling
- `CoreError` values are immutable → safe to share across threads.
- Error propagation across thread boundaries is safe.

---

## Validation Rules

### StreamInfo Validation
```text
duration ≥ 0.0
sampleRate > 0.0 (typically 8000.0 .. 384000.0)
channels ≥ 1 (typically 1 or 2, max 8)
bitDepth ≥ 8 (typically 16, 24, 32)
```

### TagBundle Validation
```text
year: if present, 1000 ≤ year ≤ 9999 (reasonable range)
trackNumber: if present, trackNumber ≥ 1
discNumber: if present, discNumber ≥ 1
artworkData: if present, size ≤ 10 MB (recommended)
```

Implementations SHOULD validate inputs and throw `CoreError.invalidArgument` for invalid values.

---

## Future Extensions (Reserved)

The following models may be added in future versions:

### PlaybackOptions
- Repeat mode (none, one, all)
- Shuffle mode
- Crossfade settings
- Gapless playback settings

### EqualizerBand
- Frequency, gain, Q-factor
- For parametric EQ support

### PlaylistEntry
- Track reference
- Position in queue
- User metadata (play count, rating, etc.)

Any future model MUST:
1. Be platform-neutral.
2. Be representable in both Swift and C++20.
3. Have clear semantics documented.
4. Pass cross-platform serialization tests if persisted.