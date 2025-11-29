# 03. Ports Specification

This document defines the abstract Port interfaces that form the boundary between
HarmoniaCore's platform-neutral logic and platform-specific adapters.

All content in this specification is written in English and is language-neutral.
Code samples are illustrative only; actual implementations MUST follow the semantics
defined here while using idiomatic syntax for their target language.

---

## Port Design Principles

1. **Platform Independence**  
   Ports MUST NOT reference any platform-specific types or APIs.  
   All types crossing the Port boundary MUST be defined in `05_models.md`.

2. **Thread Safety**  
   All Ports MUST be safe to call from any thread unless explicitly documented otherwise.  
   Implementations MUST provide appropriate synchronization.

3. **Error Handling**  
   All recoverable errors MUST be signaled via `CoreError` (defined in `05_models.md`).  
   Error mapping rules are defined in `01_architecture.md`.

4. **Minimal Surface**  
   Ports define only essential operations required for cross-platform behavior parity.

---

## LoggerPort

Provides structured logging for debugging and parity validation.

### Interface

```text
protocol LoggerPort {
    debug(msg: String)
    info(msg: String)
    warn(msg: String)
    error(msg: String)
}
```

### Semantics

- **Thread Safety:** MUST be safe to call from any thread concurrently.
- **Performance:** Implementations SHOULD use lazy evaluation to avoid string formatting overhead when logging is disabled.
- **Output:** Implementations MAY output to any destination (console, file, system logger, etc.).
- **Format:** Implementations SHOULD include timestamp and log level in output.

---

## ClockPort

Provides monotonic time for timing measurements and parity validation.

### Interface

```text
protocol ClockPort {
    now() -> UInt64  // monotonic nanoseconds since unspecified epoch
}
```

### Semantics

- **Monotonic Guarantee:** Returned values MUST NEVER decrease, even across system sleep/wake.
- **Precision:** MUST provide nanosecond resolution or better. If native precision is lower (e.g., microseconds), implementations MUST convert to nanoseconds.
- **Epoch:** The epoch is unspecified and implementation-defined. Only relative differences between calls are meaningful.
- **Thread Safety:** MUST be safe to call from any thread concurrently without synchronization.
- **Real-Time Safety:** SHOULD be safe to call from real-time audio threads (no allocations, no blocking).

### Usage

```text
let start = clock.now()
// ... perform operation ...
let end = clock.now()
let elapsed_ns = end - start
```

---

## FileAccessPort

Provides platform-neutral file I/O.

### Types

```text
type FileHandleToken  // opaque handle (implementation-defined)
```

### Interface

```text
protocol FileAccessPort {
    open(url: String) throws -> FileHandleToken
    read(token: FileHandleToken, buffer: UnsafeMutableRawPointer, count: Int) throws -> Int
    size(token: FileHandleToken) throws -> Int64
    close(token: FileHandleToken)
}
```

### Semantics

**open(url)**
- Opens file at `url` for reading.
- Returns opaque `FileHandleToken` on success.
- Throws `CoreError.notFound` if file does not exist.
- Throws `CoreError.ioError` for permission denied or other I/O errors.
- Thread Safety: Safe to call concurrently for different files.

**read(token, buffer, count)**
- Reads up to `count` bytes into `buffer` from file associated with `token`.
- Returns actual number of bytes read (may be less than `count` at EOF).
- Returns `0` at end of file.
- Throws `CoreError.invalidState` if `token` is invalid.
- Throws `CoreError.ioError` for I/O errors.
- Thread Safety: Safe to call concurrently with different tokens. Behavior is undefined if called concurrently with the same token.

**size(token)**
- Returns total size of file in bytes.
- Throws `CoreError.invalidState` if `token` is invalid.
- Throws `CoreError.ioError` for I/O errors.
- Thread Safety: Safe to call concurrently.

**close(token)**
- Closes file associated with `token` and releases resources.
- MUST be idempotent (safe to call multiple times).
- MUST NOT throw exceptions.
- After close, `token` becomes invalid.
- Thread Safety: Safe to call concurrently with different tokens.

### Error Handling

Implementations MUST handle platform-specific errors:
- **POSIX (Linux):** Retry on `EINTR`, handle partial reads.
- **Windows:** Handle wide-character paths, retry on transient errors.
- **macOS/iOS:** Handle sandbox restrictions, security-scoped bookmarks.

---

## DecoderPort

Decodes audio files to interleaved Float32 PCM.

### Types

```text
type DecodeHandle  // opaque handle (implementation-defined)
```

### Interface

```text
protocol DecoderPort {
    open(url: String) throws -> DecodeHandle
    read(handle: DecodeHandle, pcmInterleaved: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int
    seek(handle: DecodeHandle, toSeconds: Double) throws
    info(handle: DecodeHandle) throws -> StreamInfo
    close(handle: DecodeHandle)
}
```

### Semantics

**open(url)**
- Opens audio file at `url` and prepares for decoding.
- Returns opaque `DecodeHandle` on success.
- Throws `CoreError.notFound` if file does not exist.
- Throws `CoreError.unsupported` if file format or codec is not supported.
- Throws `CoreError.decodeError` if file is corrupted or invalid.
- Thread Safety: Safe to call concurrently for different files.

**read(handle, pcmInterleaved, maxFrames)**
- Decodes up to `maxFrames` audio frames into `pcmInterleaved` buffer.
- Output format: Interleaved Float32 PCM, range [-1.0, 1.0].
- Returns actual number of frames decoded (may be less than `maxFrames` at EOF).
- Returns `0` at end of stream.
- Throws `CoreError.invalidState` if `handle` is invalid.
- Throws `CoreError.decodeError` if decoding fails.
- Thread Safety: Undefined behavior if called concurrently with same handle. Use separate handles for concurrent decoding.

**seek(handle, toSeconds)**
- Seeks to position `toSeconds` in the audio stream.
- Next `read()` will return frames starting from this position.
- Throws `CoreError.unsupported` if seeking is not supported for this format.
- Throws `CoreError.invalidArgument` if `toSeconds` is negative or beyond stream duration.
- Throws `CoreError.invalidState` if `handle` is invalid.
- Thread Safety: Undefined behavior if called concurrently with `read()` on same handle.

**info(handle)**
- Returns `StreamInfo` describing the audio stream (see `05_models.md`).
- Throws `CoreError.invalidState` if `handle` is invalid.
- Thread Safety: Safe to call concurrently.

**close(handle)**
- Closes decoder and releases resources.
- MUST be idempotent (safe to call multiple times).
- MUST NOT throw exceptions.
- After close, `handle` becomes invalid.
- Thread Safety: Safe to call concurrently with different handles.

### Format Requirements

- **Output:** Interleaved Float32 PCM, sample values in range [-1.0, 1.0].
- **Supported Formats:** Implementations SHOULD support: WAV, AIFF, MP3, AAC, FLAC.
- **Unsupported Formats:** MUST throw `CoreError.unsupported` with descriptive message.

---

## AudioOutputPort

Outputs interleaved Float32 PCM to system audio hardware.

### Interface

```text
protocol AudioOutputPort {
    configure(sampleRate: Double, channels: Int, framesPerBuffer: Int)
    start() throws
    stop()
    render(interleavedFloat32: UnsafePointer<Float>, frameCount: Int) throws -> Int
}
```

### Semantics

**configure(sampleRate, channels, framesPerBuffer)**
- Configures audio output parameters.
- `sampleRate`: Sample rate in Hz (e.g., 44100.0, 48000.0).
- `channels`: Number of audio channels (typically 2 for stereo).
- `framesPerBuffer`: Preferred buffer size in frames (hint only; actual size may differ).
- MUST be called before `start()`.
- MAY be called while stopped to reconfigure.
- MUST NOT be called while playing.
- Thread Safety: MUST be called on main thread (platform-specific requirement).

**start()**
- Starts audio output.
- Audio hardware begins consuming data via `render()` calls.
- Throws `CoreError.invalidState` if not configured.
- Throws `CoreError.ioError` if audio device cannot be started.
- Thread Safety: MUST be called on main thread.

**stop()**
- Stops audio output.
- Audio hardware stops consuming data.
- MUST be idempotent (safe to call multiple times).
- MUST NOT throw exceptions.
- Thread Safety: MUST be called on main thread.

**render(interleavedFloat32, frameCount)**
- Provides audio data to be played.
- `interleavedFloat32`: Buffer of Float32 samples, interleaved by channel.
- `frameCount`: Number of frames in buffer.
- Returns number of frames actually consumed (may be less than `frameCount`).
- Throws `CoreError.invalidState` if output is not started.
- **Real-Time Safety:** This method MAY be called from a real-time audio thread. Implementations MUST:
  - NOT allocate memory
  - NOT block or wait
  - NOT acquire locks (use lock-free data structures)
  - Complete in bounded time

### Buffer Format

- **Interleaved:** Samples are interleaved by channel.  
  Example (2 channels): `[L0, R0, L1, R1, L2, R2, ...]`
- **Sample Range:** Float32 values in range [-1.0, 1.0].
- **Clipping:** Implementations SHOULD clip samples outside this range.

---

## TagReaderPort

Reads metadata tags from audio files.

### Interface

```text
protocol TagReaderPort {
    read(url: String) throws -> TagBundle
}
```

### Semantics

**read(url)**
- Reads metadata tags from audio file at `url`.
- Returns `TagBundle` containing extracted metadata (see `05_models.md`).
- Fields not present in file are left as `nil`/`null`/optional empty.
- Throws `CoreError.notFound` if file does not exist.
- Throws `CoreError.ioError` for I/O errors.
- Throws `CoreError.unsupported` if file format does not support metadata.
- Thread Safety: Safe to call concurrently.

### Supported Tag Formats

Implementations SHOULD support:
- **ID3v1, ID3v2** (MP3)
- **Vorbis Comments** (FLAC, Ogg Vorbis, Opus)
- **MP4 metadata** (M4A, AAC)
- **APEv2 tags** (APE, some MP3)

### Cross-Platform Consistency

- Tag mappings MUST be consistent across platforms.
- Field names MUST match `TagBundle` specification.
- Text encoding MUST be normalized to UTF-8.
- Missing tags MUST result in `nil`/`null` fields, not empty strings.

---

## TagWriterPort

Writes metadata tags to audio files.

### Interface

```text
protocol TagWriterPort {
    write(url: String, tags: TagBundle) throws
}
```

### Semantics

**write(url, tags)**
- Writes metadata tags from `tags` to audio file at `url`.
- Only writes fields present in `tags` (non-nil/non-null).
- Preserves existing tags not present in `tags`.
- Throws `CoreError.notFound` if file does not exist.
- Throws `CoreError.ioError` for I/O errors (including permission denied).
- Throws `CoreError.unsupported` if platform or file format does not support writing.
- Thread Safety: MUST synchronize file writes if called concurrently.

### Preservation Requirements

Implementations SHOULD:
- Preserve unknown tag frames/atoms not defined in `TagBundle`.
- Create backup before modifying file (optional but recommended).
- Handle read-only files gracefully (throw `CoreError.ioError`).

---

## Port Implementation Guidelines

### For Implementers

1. **Follow Semantics Exactly**  
   Observable behavior MUST match this specification, regardless of internal implementation.

2. **Error Mapping**  
   All platform errors MUST be mapped to `CoreError` categories as defined in `01_architecture.md`.

3. **Thread Safety**  
   Meet the thread-safety requirements specified for each Port.

4. **Real-Time Safety**  
   Methods called from audio threads (e.g., `AudioOutputPort.render()`) MUST NOT:
   - Allocate memory
   - Block or wait
   - Acquire locks (use lock-free data structures instead)

5. **Testing**  
   Every Port implementation MUST pass behavior parity tests defined in `api-parity.md`.

### For Service Authors

1. **Depend Only on Ports**  
   Services MUST NOT reference platform-specific adapters or APIs directly.

2. **Use Dependency Injection**  
   Receive Port implementations via constructor injection or factory.

3. **Handle All Errors**  
   All methods that throw MUST be wrapped in appropriate error handling.