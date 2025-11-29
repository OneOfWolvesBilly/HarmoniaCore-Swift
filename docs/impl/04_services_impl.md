# Services Implementation

This document provides implementation guidance for the Service layer.

**Spec Reference:** [`specs/04_services.md`](../specs/04_services.md)

---

## Key Principles

1. **Services depend only on Ports and Models** - Never import platform-specific frameworks
2. **Use dependency injection** - Receive Ports via constructor
3. **Thread safety** - Services must be thread-safe
4. **Error handling** - All errors propagate as `CoreError`

---

## Swift: DefaultPlaybackService

### Basic Structure

```swift
import Foundation

@MainActor
public final class DefaultPlaybackService: PlaybackService {
    // Dependencies (Ports)
    private let decoder: DecoderPort
    private let audio: AudioOutputPort
    private let clock: ClockPort
    private let logger: LoggerPort
    
    // Internal state
    private var currentHandle: DecodeHandle?
    private var streamInfo: StreamInfo?
    private var _state: PlaybackState = .stopped
    private var startTime: UInt64 = 0
    
    public var state: PlaybackState { _state }
    
    public init(decoder: DecoderPort,
                audio: AudioOutputPort,
                clock: ClockPort,
                logger: LoggerPort) {
        self.decoder = decoder
        self.audio = audio
        self.clock = clock
        self.logger = logger
    }
}
```

### State Management

```swift
extension DefaultPlaybackService {
    public func load(url: URL) throws {
        logger.info("Loading: \(url.path)")
        
        do {
            // Clean up previous track
            if let handle = currentHandle {
                decoder.close(handle)
                currentHandle = nil
            }
            
            // Open new track
            let handle = try decoder.open(url: url)
            let info = try decoder.info(handle)
            
            // Configure audio output
            audio.configure(
                sampleRate: info.sampleRate,
                channels: info.channels,
                framesPerBuffer: 512
            )
            
            // Update state
            currentHandle = handle
            streamInfo = info
            _state = .paused
            
            logger.info("Loaded: \(info.duration)s, \(info.sampleRate)Hz")
        } catch {
            _state = .error(error as? CoreError ?? .ioError(underlying: error))
            throw error
        }
    }
    
    public func play() throws {
        guard let handle = currentHandle else {
            throw CoreError.invalidState("No track loaded")
        }
        
        guard _state != .playing else {
            return // Idempotent
        }
        
        try audio.start()
        _state = .playing
        startTime = clock.now()
        
        logger.info("Playing")
        
        // Start background decode/render loop
        startPlaybackLoop(handle: handle)
    }
    
    public func pause() {
        guard _state == .playing else {
            return // Idempotent
        }
        
        audio.stop()
        _state = .paused
        logger.info("Paused")
    }
    
    public func stop() {
        guard _state != .stopped else {
            return // Idempotent
        }
        
        audio.stop()
        
        if let handle = currentHandle {
            decoder.close(handle)
            currentHandle = nil
        }
        
        streamInfo = nil
        _state = .stopped
        logger.info("Stopped")
    }
}
```

### Position Tracking

```swift
extension DefaultPlaybackService {
    public func currentTime() -> Double {
        switch _state {
        case .playing:
            let elapsed = clock.now() - startTime
            return Double(elapsed) / 1_000_000_000.0 // Convert ns to seconds
        case .paused:
            // Return last known position
            return 0.0 // Simplified - should track actual position
        case .stopped, .error:
            return 0.0
        case .buffering:
            return 0.0
        }
    }
    
    public func duration() -> Double {
        return streamInfo?.duration ?? 0.0
    }
    
    public func seek(to seconds: Double) throws {
        guard let handle = currentHandle else {
            throw CoreError.invalidState("No track loaded")
        }
        
        guard seconds >= 0 else {
            throw CoreError.invalidArgument("Seek position must be >= 0")
        }
        
        guard let info = streamInfo, seconds <= info.duration else {
            throw CoreError.invalidArgument("Seek position beyond duration")
        }
        
        try decoder.seek(handle, to: seconds)
        logger.info("Seeked to \(seconds)s")
    }
}
```

### Background Playback Loop

```swift
extension DefaultPlaybackService {
    private func startPlaybackLoop(handle: DecodeHandle) {
        Task {
            let bufferSize = 4096 // frames
            var buffer = [Float](repeating: 0, count: bufferSize * 2) // Stereo
            
            while _state == .playing {
                do {
                    // Decode frames
                    let framesRead = try decoder.read(
                        handle,
                        into: &buffer,
                        maxFrames: bufferSize
                    )
                    
                    guard framesRead > 0 else {
                        // End of stream
                        await MainActor.run {
                            stop()
                        }
                        break
                    }
                    
                    // Render to audio output
                    _ = try audio.render(buffer, frameCount: framesRead)
                    
                } catch {
                    logger.error("Playback error: \(error)")
                    await MainActor.run {
                        _state = .error(error as? CoreError ?? .decodeError("\(error)"))
                    }
                    break
                }
            }
        }
    }
}
```

---

## C++20: DefaultPlaybackService (Planned)

### Basic Structure

```cpp
class DefaultPlaybackService : public PlaybackService {
private:
    std::unique_ptr<DecoderPort> decoder_;
    std::unique_ptr<AudioOutputPort> audio_;
    std::shared_ptr<ClockPort> clock_;
    std::shared_ptr<LoggerPort> logger_;
    
    std::optional<DecodeHandle> current_handle_;
    std::optional<StreamInfo> stream_info_;
    PlaybackState state_ = PlaybackState::Stopped;
    
    mutable std::mutex mutex_;
    std::atomic<bool> should_stop_{false};
    std::thread playback_thread_;

public:
    DefaultPlaybackService(
        std::unique_ptr<DecoderPort> decoder,
        std::unique_ptr<AudioOutputPort> audio,
        std::shared_ptr<ClockPort> clock,
        std::shared_ptr<LoggerPort> logger)
        : decoder_(std::move(decoder))
        , audio_(std::move(audio))
        , clock_(std::move(clock))
        , logger_(std::move(logger)) {}
    
    ~DefaultPlaybackService() {
        stop();
    }
    
    void load(const std::string& url) override {
        logger_->info("Loading: " + url);
        
        std::lock_guard lock(mutex_);
        
        // Clean up previous
        if (current_handle_) {
            decoder_->close(*current_handle_);
            current_handle_.reset();
        }
        
        // Open new
        auto handle = decoder_->open(url);
        auto info = decoder_->info(handle);
        
        audio_->configure(info.sample_rate, info.channels, 512);
        
        current_handle_ = handle;
        stream_info_ = info;
        state_ = PlaybackState::Paused;
        
        logger_->info("Loaded successfully");
    }
    
    void play() override {
        std::lock_guard lock(mutex_);
        
        if (!current_handle_) {
            throw CoreError::InvalidState("No track loaded");
        }
        
        if (state_ == PlaybackState::Playing) {
            return; // Idempotent
        }
        
        audio_->start();
        state_ = PlaybackState::Playing;
        should_stop_ = false;
        
        // Start playback thread
        playback_thread_ = std::thread([this]() {
            playbackLoop();
        });
        
        logger_->info("Playing");
    }
    
    void pause() override {
        std::lock_guard lock(mutex_);
        
        if (state_ != PlaybackState::Playing) {
            return; // Idempotent
        }
        
        should_stop_ = true;
        if (playback_thread_.joinable()) {
            playback_thread_.join();
        }
        
        audio_->stop();
        state_ = PlaybackState::Paused;
        logger_->info("Paused");
    }
    
    void stop() override {
        std::lock_guard lock(mutex_);
        
        if (state_ == PlaybackState::Stopped) {
            return; // Idempotent
        }
        
        should_stop_ = true;
        if (playback_thread_.joinable()) {
            playback_thread_.join();
        }
        
        audio_->stop();
        
        if (current_handle_) {
            decoder_->close(*current_handle_);
            current_handle_.reset();
        }
        
        stream_info_.reset();
        state_ = PlaybackState::Stopped;
        logger_->info("Stopped");
    }

private:
    void playbackLoop() {
        constexpr int buffer_size = 4096;
        std::vector<float> buffer(buffer_size * 2); // Stereo
        
        while (!should_stop_) {
            std::lock_guard lock(mutex_);
            
            if (!current_handle_) break;
            
            int frames_read = decoder_->read(
                *current_handle_,
                buffer.data(),
                buffer_size
            );
            
            if (frames_read <= 0) {
                // End of stream
                state_ = PlaybackState::Stopped;
                break;
            }
            
            audio_->render(buffer.data(), frames_read);
        }
    }
};
```

---

## Factory Pattern

### Swift Factory

```swift
public enum CoreFactory {
    public static func makePlaybackService() -> PlaybackService {
        let logger = OSLogAdapter()
        let clock = MonotonicClockAdapter()
        let decoder = AVAssetReaderDecoderAdapter(logger: logger)
        let audio = AVAudioEngineOutputAdapter(logger: logger)
        
        return DefaultPlaybackService(
            decoder: decoder,
            audio: audio,
            clock: clock,
            logger: logger
        )
    }
}

// Usage
let service = CoreFactory.makePlaybackService()
```

### C++20 Factory

```cpp
class LinuxCoreFactory {
public:
    static std::unique_ptr<PlaybackService> makePlaybackService() {
        auto logger = std::make_shared<StdErrLogger>();
        auto clock = std::make_shared<SteadyClockAdapter>();
        auto decoder = std::make_unique<FFmpegDecoderAdapter>(logger);
        auto audio = std::make_unique<PipeWireOutputAdapter>(logger);
        
        return std::make_unique<DefaultPlaybackService>(
            std::move(decoder),
            std::move(audio),
            clock,
            logger
        );
    }
};

// Usage
auto service = LinuxCoreFactory::makePlaybackService();
```

---

## Testing

### Mock Ports for Testing

**Swift:**
```swift
class MockDecoderPort: DecoderPort {
    var openCalled = false
    var readCount = 0
    
    func open(url: URL) throws -> DecodeHandle {
        openCalled = true
        return DecodeHandle(id: UUID())
    }
    
    func read(_ handle: DecodeHandle, 
              into buffer: UnsafeMutablePointer<Float>, 
              maxFrames: Int) throws -> Int {
        readCount += 1
        return maxFrames // Simulate successful read
    }
    
    // ... other methods
}

// Test
let mockDecoder = MockDecoderPort()
let service = DefaultPlaybackService(
    decoder: mockDecoder,
    audio: mockAudio,
    clock: mockClock,
    logger: NoopLogger()
)

try service.load(url: testURL)
XCTAssertTrue(mockDecoder.openCalled)
```

---

## Implementation Checklist

- [ ] Services depend only on Ports (no platform imports)
- [ ] All dependencies injected via constructor
- [ ] Thread-safe state management
- [ ] Proper error handling and propagation
- [ ] Resource cleanup in deinit/destructor
- [ ] Idempotent operations (play/pause/stop)
- [ ] Comprehensive logging for debugging