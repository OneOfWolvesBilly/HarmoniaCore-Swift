# Apple Adapters (AVFoundation / macOS + iOS)

## Overview

Apple adapters implement the common Ports using system frameworks:

| Port | Adapter | Framework | Platforms | Notes |
|------|----------|------------|------------|-------|
| **AudioOutputPort** | `AVAudioEngineOutputAdapter` | AVFoundation / AVFAudio | iOS / macOS | Uses `AVAudioEngine` + `AVAudioPlayerNode`. Handles sample rate via `AVAudioFormat`. |
| **DecoderPort** | `AVAssetReaderDecoderAdapter` | AVFoundation | iOS / macOS | Reads MP3, AAC, ALAC, WAV, AIFF, and CAF. |
| **DecoderPort (Pro)** | `FlacDecoderAdapter` | Embedded C (`dr_flac` / `libFLAC`) | macOS Pro | Converts FLAC → Float32 PCM. |
| **DecoderPort (Pro)** | `DsdDecoderAdapter` | Embedded C (`dsd2pcm`) | macOS Pro | Converts DSF / DFF → PCM. |
| **FileAccessPort** | `SandboxFileAccessAdapter` | Foundation / Security | iOS / macOS | Manages sandbox-scoped URLs. |
| **TagReaderPort** | `AVMetadataTagReaderAdapter` | AVFoundation | iOS / macOS | Reads ID3 / MP4 metadata. |
| **TagWriterPort** | `AVMutableTagWriterAdapter` | AVFoundation | iOS / macOS | Always throws `CoreError.unsupported` (see note below). |
| **ClockPort** | `MonotonicClockAdapter` | Dispatch / mach | iOS / macOS | Uses `DispatchTime.now().uptimeNanoseconds`. |
| **LoggerPort** | `OSLogAdapter` | os.log | iOS / macOS | Uses unified logging; fallback to no-op. |
| **LoggerPort** | `NoopLogger` | N/A | iOS / macOS | Discards all messages (used in tests). |

---

## 1. Adapter Responsibilities

Each adapter implements one Port interface and translates platform-specific APIs into HarmoniaCore-neutral data types.

- Must conform to the semantics defined in `03_ports.md`.  
- Must propagate recoverable errors as `CoreError` categories (see [Error Mapping](#3-error-mapping)).  
- Must pass validation through `api-parity.md`.  
- Must meet thread-safety requirements specified in `01_architecture.md`.

---

## 2. Behavioral Specifications

### 2.1 OSLogAdapter : LoggerPort

- Forwards messages to Unified Logging (`os.Logger`).  
- Falls back to no-op logging if unified logging is unavailable.
- Thread-safe for concurrent logging from multiple threads.

---

### 2.2 NoopLogger : LoggerPort

- Discards all messages; used for silent or test builds.
- Zero-overhead implementation.
- Thread-safe (no-op operations are inherently safe).

---

### 2.3 MonotonicClockAdapter : ClockPort

- Returns monotonic time in nanoseconds using `DispatchTime.now().uptimeNanoseconds`.
- Monotonic guarantee: Time never goes backwards, even across system sleep.
- Precision: Nanosecond resolution.
- Thread-safe: Can be called from any thread without synchronization.

---

### 2.4 SandboxFileAccessAdapter : FileAccessPort

- Opens files in a sandbox-safe way via `FileHandle`.  
- Tracks handles using `FileHandleToken(UUID)`.  
- Implements `open`, `read`, `size`, and `close`.
- Thread-safe: Maintains thread-local or synchronized file handle access.

**Security Considerations:**
- Respects iOS sandbox restrictions.
- Requires security-scoped bookmarks for persistent file access on iOS.
- All file operations validate sandbox permissions before execution.

---

### 2.5 AVAssetReaderDecoderAdapter : DecoderPort

- Uses `AVAssetReader` to decode media into interleaved Float32 PCM.  
- Must support `open`, `read`, `seek`, `info`, and `close`.  
- Automatically handles compressed → PCM conversion.
- Thread-safe: Decoding operations can be performed on background threads.

**Supported Formats:**
- MP3 (MPEG-1/2 Layer 3)
- AAC (Advanced Audio Coding)
- ALAC (Apple Lossless)
- WAV (PCM)
- AIFF (Audio Interchange File Format)
- CAF (Core Audio Format)

**Limitations:**
- FLAC: Not supported (use `FlacDecoderAdapter` on macOS Pro when available)
- DSD: Not supported (use `DsdDecoderAdapter` on macOS Pro when available)
- Opus/Vorbis: Not natively supported by AVFoundation

---

### 2.6 FlacDecoderAdapter : DecoderPort (macOS Pro)

- Uses **libFLAC** or **dr_flac** for FLAC decoding.
- Converts FLAC → interleaved Float32 PCM.
- Only available in macOS Pro builds (requires static linking of libFLAC).
- On standard builds, attempting to decode FLAC throws `CoreError.unsupported`.

---

### 2.7 DsdDecoderAdapter : DecoderPort (macOS Pro)

- Uses **dsd2pcm** library for DSD to PCM conversion.
- Supports DSF and DFF container formats.
- Only available in macOS Pro builds (requires static linking of dsd2pcm).
- On standard builds, attempting to decode DSD throws `CoreError.unsupported`.

**Conversion Parameters:**
- Output format: Float32 PCM
- Typical conversion: DSD64 → 352.8 kHz PCM

---

### 2.8 AVAudioEngineOutputAdapter : AudioOutputPort

- Uses `AVAudioEngine` and `AVAudioPlayerNode` for playback.  
- Handles device sample-rate conversion and buffer scheduling.  
- Should ensure real-time safe operations for render callbacks.
- Typically operates on `@MainActor` for iOS/macOS UI integration.

**Thread Safety:**
- Configuration methods: Main thread only
- Render callback: Real-time safe, no allocations
- State changes: Synchronized with audio engine state

---

### 2.9 AVMetadataTagReaderAdapter : TagReaderPort

- Reads ID3 / MP4 metadata using `AVAsset` APIs.  
- Maps metadata into HarmoniaCore's `TagBundle`.
- Thread-safe: Metadata reading can be performed on background threads.

**Supported Tags:**
- Common metadata: Title, Artist, Album, Album Artist
- Extended metadata: Genre, Year, Track Number, Disc Number
- Artwork: Embedded cover art as raw image data

---

### 2.10 AVMutableTagWriterAdapter : TagWriterPort

- Uses `AVMutableMetadataItem` for writable metadata where supported.  
- **Currently throws `CoreError.unsupported` on all platforms.**
- **iOS:** All write attempts throw due to sandbox restrictions.
- **macOS:** Support deferred; currently throws for consistency.

**Future Plans:**
- May provide limited macOS-only tag editing in future versions.
- iOS will remain read-only due to fundamental sandbox limitations.

---

## 3. Error Mapping

All AVFoundation errors MUST be mapped to `CoreError` categories:

| AVFoundation Error | CoreError | Example |
|-------------------|-----------|---------|
| `AVError.fileNotFound` | `CoreError.notFound` | "File not found: /path/to/file.mp3" |
| `AVError.unsupportedOutputSettings` | `CoreError.unsupported` | "Output format not supported: 384kHz" |
| `AVError.decoderNotFound` | `CoreError.unsupported` | "No decoder available for codec: opus" |
| `AVError.decodeFailed` | `CoreError.decodeError` | "Decode failed at frame 12345" |
| Permission denied | `CoreError.ioError` | Wrap underlying NSError |
| Other NSError | `CoreError.ioError` | Include error code and description |

---

## 4. Platform Constraints

- **iOS** sandbox forbids arbitrary file writes; all write attempts must throw `.unsupported`.  
- **macOS Pro** builds may statically link `libFLAC` and `dsd2pcm`; license headers must be preserved.  
- **AVFoundation** performs implicit decoding to PCM for playback; double-decoding must be avoided.  
- All adapters MUST handle AVFoundation's asynchronous callbacks appropriately.
- Audio engine operations (start/stop) SHOULD be called on the main thread for UI synchronization.

---

## 5. Example Instantiation

```swift
import HarmoniaCore

// Standard build
let logger = OSLogAdapter()
let audio: AudioOutputPort = AVAudioEngineOutputAdapter(logger: logger)
let decoder: DecoderPort = AVAssetReaderDecoderAdapter(logger: logger)
let clock = MonotonicClockAdapter()
let fileAccess = SandboxFileAccessAdapter()

let svc = PlaybackService(
    audio: audio,
    decoder: decoder,
    clock: clock,
    logger: logger,
    fileAccess: fileAccess
)

// macOS Pro build with FLAC support (planned)
#if HARMONIA_PRO_BUILD
let flacDecoder: DecoderPort = FlacDecoderAdapter(logger: logger)
// Use flacDecoder for .flac files
#endif
```

---

## 6. Validation Checklist

| Requirement | Description |
|-------------|-------------|
| Behavior parity | Must produce identical observable playback results as Linux adapters. |
| Error handling | All errors mapped to `CoreError`. |
| Thread safety | AVFoundation calls properly synchronized; no background thread violations. |
| CI coverage | Will be included in CI parity workflow. |
| Documentation | All adapters documented with usage examples. |