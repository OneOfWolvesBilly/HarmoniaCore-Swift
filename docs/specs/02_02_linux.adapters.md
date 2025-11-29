# Linux Adapters (PipeWire / ALSA / libsndfile)

## Overview

Linux adapters implement the same Ports using native libraries:

| Port | Adapter | Library | Notes |
|------|----------|----------|-------|
| **AudioOutputPort** | `PipeWireOutputAdapter` | PipeWire | Real-time low-latency playback. Uses ring buffer to push PCM frames. Auto-fallback to ALSA if PipeWire unavailable. |
| **DecoderPort** | `FFmpegDecoderAdapter` | FFmpeg | Primary decoder; supports WAV, AIFF, FLAC, MP3, AAC, Opus, Vorbis. May require non-free license flag for some codecs. |
| **DecoderPort (fallback)** | `LibSndFileDecoderAdapter` | libsndfile / libFLAC | Fallback decoder; supports WAV, AIFF, FLAC; can use mpg123 for MP3. |
| **FileAccessPort** | `PosixFileAccessAdapter` | POSIX syscalls | Implements `open`, `read`, `lseek`, and `close`. |
| **TagReaderPort** | `TagLibTagReaderAdapter` | TagLib | Reads ID3, Vorbis, and MP4 metadata. |
| **TagWriterPort** | `TagLibTagWriterAdapter` | TagLib | Writes common metadata tags. |
| **ClockPort** | `SteadyClockAdapter` | std::chrono | Provides monotonic time for latency metrics. |
| **LoggerPort** | `SpdlogAdapter` | spdlog | Structured logging. |
| **LoggerPort (fallback)** | `StdErrLogger` | iostream | Stderr fallback for environments without spdlog. |

---

## 1. Adapter Responsibilities

Each adapter provides a concrete implementation of a HarmoniaCore Port.

- Must follow interfaces defined in `03_ports.md`.  
- Must translate native errors into `CoreError` categories (see [Error Mapping](#3-error-mapping)).  
- Must behave deterministically across platforms (see `api-parity.md`).  
- Must meet thread-safety requirements specified in `01_architecture.md`.

---

## 2. Behavioral Specifications

### 2.1 StdErrLogger : LoggerPort

- Writes messages to `stderr` using minimal formatting.  
- Must be safe for use in early-init or fallback contexts.
- Thread-safe: Must handle concurrent writes from multiple threads.
- Zero external dependencies.

---

### 2.2 SpdlogAdapter : LoggerPort

- Uses the **spdlog** library for structured logging.  
- Should default to console output if spdlog sinks are unavailable.
- Thread-safe: spdlog provides thread-safe logging by default.
- Supports multiple log levels and custom formatters.

**Expected Features:**
- Asynchronous logging for performance
- File rotation for persistent logs
- Configurable log patterns
- Multiple sinks (console, file, syslog)

---

### 2.3 SteadyClockAdapter : ClockPort

- Provides monotonic timestamps via `std::chrono::steady_clock`.  
- Used for latency measurements and deterministic timing.
- Monotonic guarantee: Time never goes backwards.
- **Precision requirement:** Must provide at least nanosecond resolution or convert to nanoseconds.
- Thread-safe: Can be called from any thread without synchronization.

**Note:** If `steady_clock` precision is lower than nanosecond (e.g., microsecond on some systems),
the adapter MUST still return nanoseconds by multiplying the value appropriately.

---

### 2.4 PosixFileAccessAdapter : FileAccessPort

- Wraps POSIX syscalls (`open`, `read`, `lseek`, `close`).  
- Must handle partial reads and `EINTR` retries gracefully.  
- Should not perform any blocking I/O on main thread.
- Thread-safe: Must handle concurrent file operations safely.

**Error Handling Requirements:**
- `ENOENT` → `CoreError.notFound`
- `EACCES`, `EPERM` → `CoreError.ioError`
- `EINTR` → Retry operation automatically
- Other errno values → `CoreError.ioError` with descriptive message

---

### 2.5 FFmpegDecoderAdapter : DecoderPort

- Uses FFmpeg (`libavformat`, `libavcodec`) to decode audio streams.  
- Must support `open`, `read`, `seek`, and `close`.  
- Optional in distributions where FFmpeg license terms restrict usage.
- Thread-safe: Decoding operations must be safe to perform on background threads.

**Supported Formats:**
- Compressed: MP3, AAC, Opus, Vorbis
- Lossless: FLAC, ALAC
- Uncompressed: WAV, AIFF

**License Considerations:**
- Some codecs (e.g., AAC, H.264) may require non-free license flags
- Distribution packages should respect local licensing requirements
- Adapter MUST detect missing codecs and throw `CoreError.unsupported` appropriately

---

### 2.6 LibSndFileDecoderAdapter : DecoderPort

- Uses **libsndfile** or **libFLAC** for uncompressed and FLAC decoding.  
- May delegate MP3 decoding to **mpg123** if available.  
- Must output interleaved Float32 PCM.
- Thread-safe: Must handle concurrent decoding operations.

**Supported Formats:**
- Primary: WAV, AIFF, FLAC (via libFLAC extension)
- Optional: MP3 (via mpg123 integration)

**Usage Priority:**
1. Use as fallback when FFmpeg is unavailable or restricted
2. Use for simple applications that don't need advanced codec support
3. Simpler dependency chain than FFmpeg

---

### 2.7 PipeWireOutputAdapter : AudioOutputPort

- Streams PCM to PipeWire or ALSA depending on environment.  
- Must support non-blocking writes and low-latency operation.  
- Handles sample rate negotiation and buffer underflow gracefully.
- Thread-safe: Render callback must be real-time safe.

**Runtime Behavior:**
1. **Detect PipeWire availability**
   - Check for PipeWire daemon at runtime
   - Fall back to ALSA if PipeWire unavailable

2. **Sample Rate Negotiation**
   - Query device supported sample rates
   - Resample if necessary (prefer hardware native rate)

3. **Buffer Management**
   - Use lock-free ring buffer for audio data
   - Handle underruns by inserting silence
   - Log underruns for debugging

**Real-Time Safety:**
- Render callback MUST NOT allocate memory
- Render callback MUST NOT block or wait
- Render callback MUST NOT acquire locks (use lock-free queues)

---

### 2.8 TagLibTagReaderAdapter : TagReaderPort

- Reads ID3, Vorbis, MP4, and FLAC metadata through **TagLib**.  
- Maps tags to `TagBundle` representation.
- Thread-safe: Metadata reading can be performed on background threads.

**Supported Tag Formats:**
- ID3v1, ID3v2 (MP3)
- Vorbis Comments (FLAC, Ogg Vorbis, Opus)
- MP4 metadata (M4A, AAC)
- APEv2 tags

**Cross-Platform Consistency:**
- Tag mappings MUST match Apple's `AVMetadataTagReaderAdapter`
- Handle missing tags gracefully (return empty optional fields)
- Normalize encoding to UTF-8

---

### 2.9 TagLibTagWriterAdapter : TagWriterPort

- Writes supported tags via **TagLib**.  
- Should preserve unrecognized frames when possible.
- Thread-safe: Must synchronize file writes.

**Writable Fields:**
- Title, Artist, Album, Album Artist
- Genre, Year
- Track Number, Disc Number
- Artwork (embedded images)

**Preservation Requirements:**
- MUST preserve unknown tag frames
- MUST NOT corrupt file if write fails
- SHOULD create backup before write operation
- MUST handle read-only files gracefully

---

## 3. Error Mapping

All Linux-specific errors MUST be mapped to `CoreError` categories:

| Source Error | CoreError | Example |
|-------------|-----------|---------|
| `errno == ENOENT` | `CoreError::NotFound` | "File not found: /path/to/file.mp3" |
| `errno == EACCES`, `EPERM` | `CoreError::IoError` | "Permission denied: /path/to/file.mp3" |
| `AVERROR_DECODER_NOT_FOUND` | `CoreError::Unsupported` | "No decoder available for codec: opus" |
| `AVERROR_INVALIDDATA` | `CoreError::DecodeError` | "Invalid audio data at frame 12345" |
| TagLib null file | `CoreError::NotFound` | "Cannot open file for tag reading" |
| TagLib save failed | `CoreError::IoError` | "Failed to save tags: permission denied" |
| Other errors | `CoreError::IoError` | Include errno description via `strerror()` |

---

## 4. Platform Constraints

- Ensure **PipeWire development libraries** (`libpipewire-0.3-dev`) are installed.  
- **FFmpegDecoderAdapter** requires optional non-free components; respect distribution policies.  
- **TagLib** version must match Apple metadata semantics for cross-platform parity.  
- All file paths should be UTF-8 encoded and normalized.  
- Must handle case-sensitive file systems (unlike macOS).
- Must respect standard Linux directory structures (`/usr/share`, `/home`, etc.).

**Distribution-Specific Considerations:**

| Distribution | FFmpeg Availability | PipeWire Availability | Notes |
|--------------|--------------------|-----------------------|-------|
| Ubuntu 22.04+ | Full | Yes | Standard repositories |
| Debian | Restricted | Yes | Some codecs in non-free |
| Fedora | Full | Yes | Full codec support |
| Arch Linux | Full | Yes | All codecs available |

---

## 5. Example C++ Adapter Stub

```cpp
class PipeWireOutputAdapter : public AudioOutputPort {
private:
    pw_stream* stream_ = nullptr;
    double sample_rate_ = 44100.0;
    int channels_ = 2;
    int frames_per_buffer_ = 512;

public:
    void configure(double sample_rate, int channels, int frames_per_buffer) override {
        sample_rate_ = sample_rate;
        channels_ = channels;
        frames_per_buffer_ = frames_per_buffer;
        
        // Initialize PipeWire stream
        // Set up audio format
    }
    
    void start() override {
        if (stream_) {
            pw_stream_set_active(stream_, true);
        }
    }
    
    void stop() override {
        if (stream_) {
            pw_stream_set_active(stream_, false);
        }
    }
    
    int render(const float* interleaved, int frame_count) override {
        // Write to ring buffer or directly to PipeWire
        // Return number of frames actually consumed
        return frame_count;
    }
};
```

---

## 6. Validation Checklist

| Requirement | Description |
|-------------|-------------|
| Behavior parity | Frame output and seek behavior must match Swift implementation. |
| Error mapping | All recoverable errors mapped to `CoreError`. |
| Timing consistency | All timestamps derived from `ClockPort` for deterministic logs. |
| Thread safety | PipeWire and FFmpeg must operate safely on worker threads. |
| CI integration | Validated through `ctest` parity workflow on GitHub Actions. |