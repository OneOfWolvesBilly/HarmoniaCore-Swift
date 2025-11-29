# Ports Implementation

This document provides concrete Swift and C++20 implementations of all Port interfaces.

**Spec Reference:** [`specs/03_ports.md`](../specs/03_ports.md)

---

## Swift: LoggerPort

```swift
/// Protocol for structured logging with lazy evaluation support.
public protocol LoggerPort: Sendable {
    func debug(_ msg: @autoclosure () -> String)
    func info(_ msg: @autoclosure () -> String)
    func warn(_ msg: @autoclosure () -> String)
    func error(_ msg: @autoclosure () -> String)
}
```

**Key Features:**
- Thread-safe: Can be called from any thread concurrently
- Lazy evaluation: `@autoclosure` avoids string formatting when disabled
- Sendable: Safe for use in Swift Concurrency

**Usage:**
```swift
let logger: LoggerPort = OSLogAdapter()
logger.info("Playback started")
logger.error("Failed to decode frame at position \(position)")
```

---

## Swift: ClockPort

```swift
/// Protocol for accessing monotonic system time.
public protocol ClockPort: Sendable {
    /// Returns monotonic time in nanoseconds since an unspecified epoch.
    func now() -> UInt64
}
```

**Key Features:**
- Monotonic: Never goes backwards, even across system sleep/wake
- Nanosecond precision
- Thread-safe and real-time safe

**Usage:**
```swift
let clock: ClockPort = MonotonicClockAdapter()
let start = clock.now()
// ... perform operation ...
let elapsed = clock.now() - start
print("Operation took \(elapsed) nanoseconds")
```

---

## Swift: FileAccessPort

```swift
/// Opaque token representing an open file handle.
public struct FileHandleToken: Hashable, Sendable {
    let id: UUID
    public init(id: UUID) { self.id = id }
}

/// Origin for seek operations.
public enum FileSeekOrigin {
    case start    // Seek from beginning of file
    case current  // Seek from current position
    case end      // Seek from end of file
}

/// Protocol for platform-neutral file I/O operations.
public protocol FileAccessPort: AnyObject {
    func open(url: URL) throws -> FileHandleToken
    
    func read(
        _ token: FileHandleToken,
        into buffer: UnsafeMutableRawPointer,
        count: Int
    ) throws -> Int
    
    func seek(
        _ token: FileHandleToken,
        offset: Int64,
        origin: FileSeekOrigin
    ) throws
    
    func size(_ token: FileHandleToken) throws -> Int64
    func close(_ token: FileHandleToken)
}
```

**Key Features:**
- Random access via `seek()` method
- Thread-safe for different tokens
- Sandbox-aware on iOS/macOS

**Usage:**
```swift
let fileAccess: FileAccessPort = SandboxFileAccessAdapter()

let token = try fileAccess.open(url: fileURL)
defer { fileAccess.close(token) }

// Get file size
let size = try fileAccess.size(token)

// Seek to beginning
try fileAccess.seek(token, offset: 0, origin: .start)

// Read data
var buffer = [UInt8](repeating: 0, count: 1024)
let bytesRead = try buffer.withUnsafeMutableBytes { ptr in
    try fileAccess.read(token, into: ptr.baseAddress!, count: 1024)
}

// Skip forward 100 bytes
try fileAccess.seek(token, offset: 100, origin: .current)

// Seek to 100 bytes before end
try fileAccess.seek(token, offset: -100, origin: .end)
```

---

## Swift: DecoderPort

```swift
/// Opaque handle representing an open decoder session.
public struct DecodeHandle: Hashable, Sendable {
    let id: UUID
    public init(id: UUID) { self.id = id }
}

/// Protocol for decoding audio files to Float32 PCM.
public protocol DecoderPort: AnyObject {
    /// Opens a decoder for the given URL (synchronous operation).
    func open(url: URL) throws -> DecodeHandle
    
    func read(
        _ handle: DecodeHandle,
        into buffer: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) throws -> Int
    
    func seek(_ handle: DecodeHandle, to seconds: Double) throws
    func info(_ handle: DecodeHandle) throws -> StreamInfo
    func close(_ handle: DecodeHandle)
}
```

**Key Features:**
- Synchronous API (matches AVFoundation's actual behavior)
- Interleaved Float32 PCM output
- Thread-safe for different handles

**Usage:**
```swift
let decoder: DecoderPort = AVAssetReaderDecoderAdapter(logger: logger)

// Open file (synchronous)
let handle = try decoder.open(url: audioURL)
defer { decoder.close(handle) }

// Get stream info
let info = try decoder.info(handle)
print("Duration: \(info.duration)s, Sample Rate: \(info.sampleRate)Hz")

// Decode audio
var buffer = [Float](repeating: 0, count: 4096 * 2)  // Stereo
let framesRead = try buffer.withUnsafeMutableBufferPointer { ptr in
    try decoder.read(handle, into: ptr.baseAddress!, maxFrames: 4096)
}

// Seek to 30 seconds
try decoder.seek(handle, to: 30.0)

// For background operation, wrap in Task:
Task.detached {
    let handle = try decoder.open(url: url)
    // ... decode ...
    decoder.close(handle)
}
```

---

## Swift: AudioOutputPort

```swift
/// Protocol for outputting audio to system hardware.
public protocol AudioOutputPort: AnyObject {
    /// Configures audio output parameters.
    /// May throw if parameters are invalid.
    func configure(
        sampleRate: Double,
        channels: Int,
        framesPerBuffer: Int
    ) throws
    
    func start() throws
    
    /// Stops audio output.
    /// Must NOT throw (as per spec).
    func stop()
    
    func render(
        _ buffer: UnsafePointer<Float>,
        frameCount: Int
    ) throws -> Int
}
```

**Key Features:**
- `configure()` can throw (e.g., unsupported sample rate)
- `stop()` must NOT throw (spec requirement)
- `render()` may be called from real-time audio thread

**Usage:**
```swift
@MainActor
func setupAudio() throws {
    let audio: AudioOutputPort = AVAudioEngineOutputAdapter(logger: logger)
    
    // Configure (can throw)
    try audio.configure(sampleRate: 44100.0, channels: 2, framesPerBuffer: 512)
    
    // Start playback
    try audio.start()
    
    // In playback loop:
    let buffer: [Float] = // ... decoded audio ...
    let framesConsumed = try buffer.withUnsafeBufferPointer { ptr in
        try audio.render(ptr.baseAddress!, frameCount: buffer.count / 2)
    }
    
    // Stop playback (never throws)
    audio.stop()
}
```

---

## Swift: TagReaderPort

```swift
/// Protocol for reading metadata tags from audio files.
public protocol TagReaderPort: AnyObject {
    /// Reads metadata from the given URL (synchronous operation).
    func read(url: URL) throws -> TagBundle
}
```

**Key Features:**
- Synchronous API (matches AVAsset.commonMetadata)
- Thread-safe
- Returns nil for missing tags

**Usage:**
```swift
let tagReader: TagReaderPort = AVMetadataTagReaderAdapter()

// Synchronous read
let tags = try tagReader.read(url: audioFileURL)

if let title = tags.title, let artist = tags.artist {
    print("\(artist) - \(title)")
}

// For background operation:
Task.detached {
    let tags = try tagReader.read(url: url)
    // ... process tags ...
}
```

---

## Swift: TagWriterPort

```swift
/// Protocol for writing metadata tags to audio files.
public protocol TagWriterPort: AnyObject {
    /// Writes tags to the audio file at the given URL.
    func write(url: URL, tags: TagBundle) throws
}
```

**Key Features:**
- Synchronous operation
- Platform-dependent support (iOS: not supported)
- Thread-safe with internal synchronization

**Usage:**
```swift
let tagWriter: TagWriterPort = AVMutableTagWriterAdapter()

var tags = TagBundle()
tags.title = "My Song"
tags.artist = "My Artist"
tags.year = 2025

do {
    try tagWriter.write(url: audioFileURL, tags: tags)
} catch CoreError.unsupported(let msg) {
    print("Tag writing not supported: \(msg)")
}
```

---

## C++20: LoggerPort

```cpp
class LoggerPort {
public:
    virtual ~LoggerPort() = default;
    
    virtual void debug(const std::string& msg) const = 0;
    virtual void info(const std::string& msg) const = 0;
    virtual void warn(const std::string& msg) const = 0;
    virtual void error(const std::string& msg) const = 0;
};
```

**Usage:**
```cpp
std::shared_ptr<LoggerPort> logger = std::make_shared<StdErrLogger>();
logger->info("Playback started");
logger->error("Failed to decode frame");
```

---

## C++20: ClockPort

```cpp
class ClockPort {
public:
    virtual ~ClockPort() = default;
    
    /// Returns monotonic time in nanoseconds.
    virtual uint64_t now() const = 0;
};
```

**Usage:**
```cpp
std::shared_ptr<ClockPort> clock = std::make_shared<SteadyClockAdapter>();

auto start = clock->now();
// ... perform operation ...
auto elapsed = clock->now() - start;
std::cout << "Operation took " << elapsed << " nanoseconds\n";
```

---

## C++20: FileAccessPort

```cpp
struct FileHandleToken {
    int fd;  // or std::string id, implementation-defined
    bool operator==(const FileHandleToken&) const = default;
};

// Hash specialization
namespace std {
    template<>
    struct hash<FileHandleToken> {
        size_t operator()(const FileHandleToken& token) const {
            return std::hash<int>{}(token.fd);
        }
    };
}

enum class FileSeekOrigin {
    Start,
    Current,
    End
};

class FileAccessPort {
public:
    virtual ~FileAccessPort() = default;
    
    virtual FileHandleToken open(const std::string& url) = 0;
    virtual int read(FileHandleToken token, void* buffer, int count) = 0;
    virtual void seek(FileHandleToken token, int64_t offset, FileSeekOrigin origin) = 0;
    virtual int64_t size(FileHandleToken token) const = 0;
    virtual void close(FileHandleToken token) = 0;
};
```

**Usage:**
```cpp
std::unique_ptr<FileAccessPort> file_access = 
    std::make_unique<PosixFileAccessAdapter>();

auto token = file_access->open("/path/to/file.mp3");

// Get file size
int64_t file_size = file_access->size(token);

// Seek to beginning
file_access->seek(token, 0, FileSeekOrigin::Start);

// Read data
std::vector<uint8_t> buffer(1024);
int bytes_read = file_access->read(token, buffer.data(), buffer.size());

// Skip forward 100 bytes
file_access->seek(token, 100, FileSeekOrigin::Current);

// Seek to 100 bytes before end
file_access->seek(token, -100, FileSeekOrigin::End);

file_access->close(token);
```

---

## C++20: DecoderPort

```cpp
struct DecodeHandle {
    int id;  // implementation-defined
    bool operator==(const DecodeHandle&) const = default;
};

namespace std {
    template<>
    struct hash<DecodeHandle> {
        size_t operator()(const DecodeHandle& h) const {
            return std::hash<int>{}(h.id);
        }
    };
}

class DecoderPort {
public:
    virtual ~DecoderPort() = default;
    
    virtual DecodeHandle open(const std::string& url) = 0;
    virtual int read(DecodeHandle handle, float* buffer, int max_frames) = 0;
    virtual void seek(DecodeHandle handle, double seconds) = 0;
    virtual StreamInfo info(DecodeHandle handle) const = 0;
    virtual void close(DecodeHandle handle) = 0;
};
```

**Usage:**
```cpp
std::unique_ptr<DecoderPort> decoder = 
    std::make_unique<FFmpegDecoderAdapter>(logger);

auto handle = decoder->open("/path/to/audio.mp3");

StreamInfo info = decoder->info(handle);
std::cout << "Duration: " << info.duration << "s\n";

std::vector<float> buffer(4096 * 2);  // Stereo
int frames_read = decoder->read(handle, buffer.data(), 4096);

decoder->seek(handle, 30.0);  // Seek to 30 seconds

decoder->close(handle);
```

---

## C++20: AudioOutputPort

```cpp
class AudioOutputPort {
public:
    virtual ~AudioOutputPort() = default;
    
    /// Configure audio parameters (can throw).
    virtual void configure(double sample_rate, int channels, int frames_per_buffer) = 0;
    
    virtual void start() = 0;
    
    /// Stop audio (must NOT throw).
    virtual void stop() = 0;
    
    virtual int render(const float* buffer, int frame_count) = 0;
};
```

**Usage:**
```cpp
std::unique_ptr<AudioOutputPort> audio = 
    std::make_unique<PipeWireOutputAdapter>(logger);

// Configure (can throw)
audio->configure(44100.0, 2, 512);

audio->start();

// In playback loop:
std::vector<float> audio_data = // ... decoded audio ...
int frames_consumed = audio->render(audio_data.data(), audio_data.size() / 2);

// Stop (never throws)
audio->stop();
```

---

## C++20: TagReaderPort

```cpp
class TagReaderPort {
public:
    virtual ~TagReaderPort() = default;
    virtual TagBundle read(const std::string& url) const = 0;
};
```

**Usage:**
```cpp
std::shared_ptr<TagReaderPort> tag_reader = 
    std::make_shared<TagLibTagReaderAdapter>();

TagBundle tags = tag_reader->read("/path/to/audio.mp3");

if (tags.title && tags.artist) {
    std::cout << *tags.artist << " - " << *tags.title << "\n";
}
```

---

## C++20: TagWriterPort

```cpp
class TagWriterPort {
public:
    virtual ~TagWriterPort() = default;
    virtual void write(const std::string& url, const TagBundle& tags) = 0;
};
```

**Usage:**
```cpp
std::shared_ptr<TagWriterPort> tag_writer = 
    std::make_shared<TagLibTagWriterAdapter>();

TagBundle tags;
tags.title = "My Song";
tags.artist = "My Artist";
tags.year = 2025;

tag_writer->write("/path/to/audio.mp3", tags);
```

---

## Port Interface Summary

| Port | Swift Protocol | C++ Abstract Class | Purpose |
|------|----------------|-------------------|---------|
| **LoggerPort** | `protocol LoggerPort: Sendable` | `class LoggerPort` | Structured logging |
| **ClockPort** | `protocol ClockPort: Sendable` | `class ClockPort` | Monotonic time |
| **FileAccessPort** | `protocol FileAccessPort: AnyObject` | `class FileAccessPort` | File I/O with seek |
| **DecoderPort** | `protocol DecoderPort: AnyObject` | `class DecoderPort` | Audio decoding |
| **AudioOutputPort** | `protocol AudioOutputPort: AnyObject` | `class AudioOutputPort` | Audio playback |
| **TagReaderPort** | `protocol TagReaderPort: AnyObject` | `class TagReaderPort` | Read metadata |
| **TagWriterPort** | `protocol TagWriterPort: AnyObject` | `class TagWriterPort` | Write metadata |

---

## Key Differences from Original Draft

### 1. FileAccessPort - Added seek() ✅

**Now includes:**
```swift
func seek(_ token: FileHandleToken, offset: Int64, origin: FileSeekOrigin) throws
```

This enables random access file operations essential for certain decoders.

### 2. DecoderPort - Synchronous API ✅

**Changed from:**
```swift
func open(url: URL) async throws -> DecodeHandle  // ❌ Old
```

**To:**
```swift
func open(url: URL) throws -> DecodeHandle  // ✅ Current
```

**Reason:** AVFoundation's core APIs are synchronous. Use `Task.detached` for background operation.

### 3. TagReaderPort - Synchronous API ✅

**Changed from:**
```swift
func read(url: URL) async throws -> TagBundle  // ❌ Old
```

**To:**
```swift
func read(url: URL) throws -> TagBundle  // ✅ Current
```

**Reason:** `AVAsset.commonMetadata` is a synchronous property.

### 4. AudioOutputPort - configure() throws, stop() doesn't ✅

**Updated:**
```swift
func configure(...) throws  // ✅ Can throw (e.g., invalid parameters)
func stop()                 // ✅ Must NOT throw (spec requirement)
```

---

## Thread Safety Summary

| Port | Thread Safety Requirement |
|------|---------------------------|
| **LoggerPort** | MUST be safe to call from any thread concurrently |
| **ClockPort** | MUST be safe to call from any thread without synchronization |
| **FileAccessPort** | Safe for different tokens; undefined for same token |
| **DecoderPort** | Safe for different handles; undefined for same handle |
| **AudioOutputPort** | `render()` MUST be real-time safe; others main thread only |
| **TagReaderPort** | MUST be safe to call from any thread concurrently |
| **TagWriterPort** | MUST synchronize file writes if called concurrently |

---

## Error Handling Patterns

### Swift Error Handling

```swift
do {
    // Synchronous operations
    let handle = try decoder.open(url: url)
    defer { decoder.close(handle) }
    
    let info = try decoder.info(handle)
    print("Duration: \(info.duration)s")
    
    // For background work, wrap in Task:
    await Task.detached {
        var buffer = [Float](repeating: 0, count: 4096 * 2)
        let frames = try decoder.read(handle, into: &buffer, maxFrames: 4096)
        return frames
    }.value
    
} catch let error as CoreError {
    switch error {
    case .notFound(let msg):
        print("File not found: \(msg)")
    case .unsupported(let msg):
        print("Format not supported: \(msg)")
    case .decodeError(let msg):
        print("Decode error: \(msg)")
    default:
        print("Error: \(error)")
    }
}
```

### C++ Error Handling

```cpp
try {
    auto handle = decoder->open("/path/to/file.mp3");
    
    // Use RAII for cleanup
    struct HandleGuard {
        DecoderPort* decoder;
        DecodeHandle handle;
        ~HandleGuard() { decoder->close(handle); }
    } guard{decoder.get(), handle};
    
    StreamInfo info = decoder->info(handle);
    std::cout << "Duration: " << info.duration << "s\n";
    
} catch (const CoreError& e) {
    switch (e.type()) {
        case CoreErrorType::NotFound:
            std::cerr << "File not found: " << e.message() << "\n";
            break;
        case CoreErrorType::Unsupported:
            std::cerr << "Format not supported: " << e.message() << "\n";
            break;
        case CoreErrorType::DecodeError:
            std::cerr << "Decode error: " << e.message() << "\n";
            break;
        default:
            std::cerr << "Error: " << e.what() << "\n";
    }
}
```

---

## Real-Time Safety Guidelines

For ports called from audio threads (especially `AudioOutputPort.render()`):

### ✅ Real-Time Safe Operations

- Read/write atomic variables
- Use lock-free data structures
- Access pre-allocated buffers
- Simple arithmetic operations
- Return immediately with bounded execution time

### ❌ NOT Real-Time Safe

- Memory allocation (`new`, `malloc`, `std::vector::push_back`)
- Blocking operations (`mutex.lock()`, `sleep()`)
- System calls (file I/O, network I/O)
- Exception throwing (prefer error codes in real-time paths)
- Unbounded loops

### Example: Lock-Free Ring Buffer

```cpp
template<typename T>
class LockFreeRingBuffer {
    std::vector<T> data_;
    std::atomic<size_t> write_pos_{0};
    std::atomic<size_t> read_pos_{0};
    size_t capacity_;

public:
    explicit LockFreeRingBuffer(size_t capacity)
        : data_(capacity), capacity_(capacity) {}
    
    // Real-time safe: no allocation, no blocking
    bool push(const T& item) {
        size_t current_write = write_pos_.load(std::memory_order_relaxed);
        size_t next_write = (current_write + 1) % capacity_;
        
        if (next_write == read_pos_.load(std::memory_order_acquire)) {
            return false;  // Buffer full
        }
        
        data_[current_write] = item;
        write_pos_.store(next_write, std::memory_order_release);
        return true;
    }
    
    bool pop(T& item) {
        size_t current_read = read_pos_.load(std::memory_order_relaxed);
        
        if (current_read == write_pos_.load(std::memory_order_acquire)) {
            return false;  // Buffer empty
        }
        
        item = data_[current_read];
        read_pos_.store((current_read + 1) % capacity_, std::memory_order_release);
        return true;
    }
};
```

---

## Testing Ports

### Unit Test Pattern (Swift)

```swift
import XCTest

class MockDecoderPort: DecoderPort {
    var openCalled = false
    var lastOpenedURL: URL?
    
    func open(url: URL) throws -> DecodeHandle {
        openCalled = true
        lastOpenedURL = url
        return DecodeHandle(id: UUID())
    }
    
    func read(_ handle: DecodeHandle, into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        return 0  // Mock implementation
    }
    
    func seek(_ handle: DecodeHandle, to seconds: Double) throws {}
    func info(_ handle: DecodeHandle) throws -> StreamInfo {
        return StreamInfo(duration: 0, sampleRate: 44100, channels: 2, bitDepth: 16)
    }
    func close(_ handle: DecodeHandle) {}
}

final class PlaybackServiceTests: XCTestCase {
    func testLoadCallsDecoder() throws {
        let mockDecoder = MockDecoderPort()
        let service = DefaultPlaybackService(
            decoder: mockDecoder,
            audio: mockAudio,
            clock: mockClock,
            logger: NoopLogger()
        )
        
        let testURL = URL(fileURLWithPath: "/test/audio.mp3")
        try service.load(url: testURL)
        
        XCTAssertTrue(mockDecoder.openCalled)
        XCTAssertEqual(mockDecoder.lastOpenedURL, testURL)
    }
}
```

### Unit Test Pattern (C++)

```cpp
#include <gtest/gtest.h>

class MockDecoderPort : public DecoderPort {
public:
    bool open_called = false;
    std::string last_opened_url;
    
    DecodeHandle open(const std::string& url) override {
        open_called = true;
        last_opened_url = url;
        return DecodeHandle{1};
    }
    
    int read(DecodeHandle handle, float* buffer, int max_frames) override {
        return 0;  // Mock implementation
    }
    
    void seek(DecodeHandle handle, double seconds) override {}
    
    StreamInfo info(DecodeHandle handle) const override {
        return StreamInfo{0, 44100, 2, 16};
    }
    
    void close(DecodeHandle handle) override {}
};

TEST(PlaybackServiceTest, LoadCallsDecoder) {
    auto mock_decoder = std::make_unique<MockDecoderPort>();
    auto* decoder_ptr = mock_decoder.get();
    
    auto service = std::make_unique<DefaultPlaybackService>(
        std::move(mock_decoder),
        std::move(mock_audio),
        std::move(mock_clock),
        std::move(mock_logger)
    );
    
    service->load("/test/audio.mp3");
    
    EXPECT_TRUE(decoder_ptr->open_called);
    EXPECT_EQ(decoder_ptr->last_opened_url, "/test/audio.mp3");
}
```

---

## Implementation Checklist

When implementing a new Port:

- [ ] Define abstract interface (protocol/class)
- [ ] Specify thread-safety requirements
- [ ] Document error conditions
- [ ] Document real-time safety (if applicable)
- [ ] Create at least one concrete adapter
- [ ] Write unit tests with mock implementations
- [ ] Document usage examples
- [ ] Ensure cross-platform behavior parity
- [ ] Validate synchronous vs asynchronous API choice
- [ ] Check that all methods match the spec exactly