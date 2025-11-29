# 02 — Adapters Overview

Adapters are platform-specific implementations of the Ports defined in `03_ports.md`.

---

## 2.1 Scope and Constraints

- Adapters reside in per‑platform source trees (`apple-swift/`, `linux-cpp/`).
- Adapters integrate platform frameworks such as AVFoundation, PipeWire, and TagLib.
- The Port boundary is strict: platform-specific types **MUST NOT** cross the boundary.
- Internal designs **MAY** differ by platform; observable behavior **MUST** remain identical.

---

## 2.2 Adapter Responsibilities

Each adapter:
1. Implements exactly one Port interface (or composes several).  
2. Translates between HarmoniaCore's neutral data types and platform APIs.  
3. Maps framework errors into the unified `CoreError` categories (see [Error Mapping Rules](./01_architecture.md#error-mapping-rules)).  
4. Ensures thread safety as required by the Port specification.  
5. Is validated by tests defined in `api-parity.md`.  

Frameworks such as **AVFoundation**, **PipeWire**, and **TagLib** are external dependencies.

---

## 2.3 Mapping Table

| Port | Apple Implementation(s) | Linux Implementation(s) |
|------|------------------------|------------------------|
| **AudioOutputPort** | `AVAudioEngineOutputAdapter` | `PipeWireOutputAdapter` |
| **DecoderPort** | `AVAssetReaderDecoderAdapter`<br>`FlacDecoderAdapter`¹<br>`DsdDecoderAdapter`¹ | `FFmpegDecoderAdapter`<br>`LibSndFileDecoderAdapter` |
| **FileAccessPort** | `SandboxFileAccessAdapter` | `PosixFileAccessAdapter` |
| **TagReaderPort** | `AVMetadataTagReaderAdapter` | `TagLibTagReaderAdapter` |
| **TagWriterPort** | `AVMutableTagWriterAdapter`² | `TagLibTagWriterAdapter` |
| **ClockPort** | `MonotonicClockAdapter` | `SteadyClockAdapter` |
| **LoggerPort** | `OSLogAdapter`<br>`NoopLogger` | `StdErrLogger`<br>`SpdlogAdapter` |

**Notes:**
1. `FlacDecoderAdapter` and `DsdDecoderAdapter` are planned for **macOS Pro builds** (require external libraries: `libFLAC`, `dsd2pcm`)
2. `AVMutableTagWriterAdapter` currently not functional (iOS sandbox restrictions; macOS support deferred)

---

## 2.4 Apple Adapters (Spec Summary)

**Platform:** macOS 12+, iOS 15+  
**Base Framework:** AVFoundation  
**Details:** [02_01_apple.adapters.md](./02_01_apple.adapters.md)

- **OSLogAdapter : LoggerPort** — Forwards messages to the Unified Logging system.  
- **NoopLogger : LoggerPort** — Discards all messages (used in tests).  
- **MonotonicClockAdapter : ClockPort** — Returns monotonic time in nanoseconds via `DispatchTime`.  
- **SandboxFileAccessAdapter : FileAccessPort** — Provides sandbox-safe file I/O using `FileHandle`.  
- **AVAssetReaderDecoderAdapter : DecoderPort** — Decodes via `AVAssetReader` to interleaved Float32 PCM.  
- **FlacDecoderAdapter : DecoderPort** — Decodes FLAC using `libFLAC` (planned for macOS Pro).  
- **DsdDecoderAdapter : DecoderPort** — Converts DSD to PCM using `dsd2pcm` (planned for macOS Pro).  
- **AVAudioEngineOutputAdapter : AudioOutputPort** — Uses `AVAudioEngine` / `AVAudioPlayerNode` for playback.  
- **AVMetadataTagReaderAdapter : TagReaderPort** — Maps AV metadata into `TagBundle`.  
- **AVMutableTagWriterAdapter : TagWriterPort** — Currently not functional (see notes).

### Decoder Selection Logic (Apple)

The Apple implementation uses the following decoder selection strategy:

1. **Standard builds (iOS, macOS):**
   - Primary: `AVAssetReaderDecoderAdapter` (supports MP3, AAC, ALAC, WAV, AIFF, CAF)
   - FLAC and DSD: Not supported (throws `CoreError.unsupported`)

2. **macOS Pro builds (planned):**
   - For FLAC files: Use `FlacDecoderAdapter` (requires `libFLAC`)
   - For DSD files (DSF/DFF): Use `DsdDecoderAdapter` (requires `dsd2pcm`)
   - For other formats: Use `AVAssetReaderDecoderAdapter`

3. **Selection is performed at runtime** based on file extension or codec detection.

---

## 2.5 Linux Adapters (Spec Summary)

**Platform:** Linux (kernel 5.10+)  
**Base Framework:** PipeWire, FFmpeg, TagLib  
**Details:** [02_02_linux.adapters.md](./02_02_linux.adapters.md)

- **StdErrLogger : LoggerPort** — Writes messages to stderr.  
- **SpdlogAdapter : LoggerPort** — Uses spdlog library for structured logging.  
- **SteadyClockAdapter : ClockPort** — Uses `std::chrono::steady_clock`.  
- **PosixFileAccessAdapter : FileAccessPort** — Wraps POSIX open/read/lseek/close.  
- **FFmpegDecoderAdapter : DecoderPort** — Uses libavformat/libavcodec for decoding.  
- **LibSndFileDecoderAdapter : DecoderPort** — Uses libsndfile for uncompressed formats.  
- **PipeWireOutputAdapter : AudioOutputPort** — Streams PCM to system audio device via PipeWire/ALSA.  
- **TagLibTagReaderAdapter : TagReaderPort** — Reads metadata using TagLib.  
- **TagLibTagWriterAdapter : TagWriterPort** — Writes metadata using TagLib.

### Decoder Selection Logic (Linux, Planned)

The Linux implementation will use the following decoder selection strategy:

1. **Primary decoder:**
   - Use `FFmpegDecoderAdapter` for all formats when available
   - Supports: MP3, AAC, FLAC, Opus, Vorbis, WAV, AIFF, and more

2. **Fallback (if FFmpeg unavailable or licensing restricted):**
   - Use `LibSndFileDecoderAdapter` for uncompressed formats (WAV, AIFF)
   - Use `LibSndFileDecoderAdapter` with FLAC extension for FLAC files
   - Use mpg123 library for MP3 (if available)

3. **Selection priority:**
   - Check FFmpeg availability and license compliance
   - Fall back to LibSndFile for supported formats
   - Throw `CoreError.unsupported` if no suitable decoder is available

4. **Distribution considerations:**
   - Some Linux distributions may restrict FFmpeg usage due to licensing
   - Adapters must detect and respect these restrictions at runtime

---

## 2.6 Platform-specific Documentation

- Apple-specific details → [`docs/specs/02_01_apple.adapters.md`](./02_01_apple.adapters.md)  
- Linux-specific details → [`docs/specs/02_02_linux.adapters.md`](./02_02_linux.adapters.md)

---

## 2.7 Testing and Validation

All adapters must pass:
- API behavior tests verifying consistent state transitions.  
- Audio decoding/output parity across platforms.  
- Metadata read/write consistency.  
- Error mapping verification to `CoreError`.  
- Thread-safety validation under concurrent access.  

Continuous Integration (CI) will run on macOS and Linux via GitHub Actions once both platforms are implemented.

---

## 2.8 Dependency and Integration Rules

- **Adapters → Ports, Models, platform APIs**  
- **Services → Ports, Models**  
- Services **MUST NOT** instantiate adapters directly; a composition root (factory) provides them.

### Composition Root (Factory Pattern)

Concrete adapter instances MUST be created by a platform-specific composition root:

**Apple (Swift) example:**
```swift
public enum AppleCoreFactory {
    public static func makePlaybackService() -> PlaybackService {
        let logger = OSLogAdapter()
        let clock = MonotonicClockAdapter()
        let audio = AVAudioEngineOutputAdapter(logger: logger)
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        
        return DefaultPlaybackService(
            audio: audio,
            decoder: decoder,
            clock: clock,
            logger: logger
        )
    }
}
```

**Linux (C++20) planned example:**
```cpp
class LinuxCoreFactory {
public:
    static std::unique_ptr makePlaybackService() {
        auto logger = std::make_shared();
        auto clock = std::make_shared();
        auto audio = std::make_unique(logger);
        auto decoder = std::make_unique(logger);
        
        return std::make_unique(
            std::move(audio),
            std::move(decoder),
            clock,
            logger
        );
    }
};
```

This ensures Services remain platform-agnostic and testable.