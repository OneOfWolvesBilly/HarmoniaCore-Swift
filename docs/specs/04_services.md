# 04. Services Specification

This document defines the HarmoniaCore service layer interfaces that are exposed
to applications. The Services constitute the primary cross-platform contract
and are built on:

- Ports defined in `03_ports.md`
- Models defined in `05_models.md`
- Platform-specific adapters (Apple / Linux) implementing those Ports

All content in this specification is written in English and is language-neutral.
Code samples are illustrative only.

---

## 4.1 Goals

1. **Cross-platform consistency**  
   The same service APIs MUST expose consistent semantics on all supported platforms.

2. **Ports-driven design**  
   Services MUST depend only on Ports and Models, never directly on AVFoundation,
   FFmpeg, PipeWire, TagLib, or any other platform-specific API.

3. **Minimal stable API surface**  
   Only core playback functionality is specified here (v0.1).
   Additional services will be specified in separate documents.

4. **Verifiable behavior**  
   Implementations MUST be testable via shared cross-platform test suites that
   exercise the same Service contracts.

---

## 4.2 PlaybackService Interface

`PlaybackService` is the primary playback control service.
All platform implementations MUST conform to the behavior defined in this section.

### 4.2.1 PlaybackState

`PlaybackState` represents the lifecycle of playback.

Normative semantics:

- **`stopped`**  
  No active playback; resources are released or reset. Position is treated as 0.

- **`playing`**  
  Audio is being rendered.

- **`paused`**  
  Playback is suspended; position is retained.

- **`buffering`**  
  *(Optional)* Waiting for decode/output; implementation MAY use this as a transient state.  
  **Note:** If used, cross-platform tests MUST account for this state. Prefer deterministic states (`playing`, `paused`) for consistency.

- **`error(CoreError)`**  
  An error state associated with a `CoreError` value.

Illustrative Swift shape:

```swift
public enum PlaybackState: Equatable {
    case stopped
    case playing
    case paused
    case buffering
    case error(CoreError)
}
```

Illustrative C++ shape:

```cpp
enum class PlaybackState {
    Stopped,
    Playing,
    Paused,
    Buffering,
    Error
};

// For C++, the associated CoreError is typically stored separately
struct PlaybackStatus {
    PlaybackState state;
    std::optional<CoreError> error;
};
```

Implementations MAY choose different concrete representations, but MUST preserve
the semantics defined above.

**State Transition Rules:**

```
[stopped] --load()--> [paused]
[paused] --play()--> [playing]
[playing] --pause()--> [paused]
[playing/paused] --stop()--> [stopped]
[any] --error--> [error]
[error] --load()--> [paused] (recovery)
```

---

### 4.2.2 Required API Surface

The following members are REQUIRED for `PlaybackService`
(terms are language-neutral; error signaling may use exceptions or error types):

1. `load(url: String)`
2. `play()`
3. `pause()`
4. `stop()`
5. `seek(to seconds: Double)`
6. `currentTime() -> Double`
7. `duration() -> Double`
8. `state: PlaybackState` (read-only)

---

#### 4.2.2.1 `load(url: String)`

- Uses configured Ports (such as `FileAccessPort` and `DecoderPort`) to open and prepare a track.
- On success:
  - Prepares audio output as needed.
  - Sets `state = paused` (track loaded but not yet playing).
  - Resets `currentTime()` to `0`.
  - Initializes `duration()` from `StreamInfo`.
- On failure:
  - Signals an appropriate `CoreError` (`ioError`, `unsupported`, etc.).
  - Sets `state = error(CoreError)`.
  - MUST NOT leave the service in an inconsistent state (e.g., partially loaded).

**Error Cases:**
- File not found → `CoreError.notFound`
- Unsupported format → `CoreError.unsupported`
- Corrupted file → `CoreError.decodeError`
- I/O error → `CoreError.ioError`

**Thread Safety:** May be called from any thread. Implementations MUST synchronize internal state.

---

#### 4.2.2.2 `play()`

- If a track is loaded and `state` is `paused` or `stopped`:
  - Starts playback via `AudioOutputPort`.
  - Sets `state = playing`.
  - Begins advancing `currentTime()`.
- If `state` is already `playing`:
  - MUST be a no-op (idempotent).
- If no track is loaded (`state = stopped` and no file loaded):
  - MUST signal `CoreError.invalidState`.

**Error Cases:**
- No track loaded → `CoreError.invalidState("No track loaded")`
- Audio device unavailable → `CoreError.ioError`

**Thread Safety:** May be called from any thread. Implementations MUST synchronize with audio rendering.

---

#### 4.2.2.3 `pause()`

- If `state` is `playing`:
  - Suspends playback via `AudioOutputPort`.
  - Retains current position.
  - Sets `state = paused`.
- If `state` is already `paused` or `stopped`:
  - MUST be a no-op (idempotent).

**Error Cases:** None (always succeeds).

**Thread Safety:** May be called from any thread.

---

#### 4.2.2.4 `stop()`

- If `state` is `playing` or `paused`:
  - Stops playback via `AudioOutputPort`.
  - Releases decoder/output resources as appropriate.
  - Resets position to `0`.
  - Sets `state = stopped`.
- If already `stopped`:
  - MUST be a no-op (idempotent).

**Error Cases:** None (always succeeds).

**Thread Safety:** May be called from any thread.

---

#### 4.2.2.5 `seek(to seconds: Double)`

- If a track is loaded and the underlying `DecoderPort` supports seeking:
  - Moves playback position to the requested time.
  - Updates the internal position used by `currentTime()`.
  - If `playing`, continues playing from new position.
  - If `paused`, remains paused at new position.
- If `seconds` is negative or beyond `duration()`:
  - MUST signal `CoreError.invalidArgument`.
- If seeking is not supported by the decoder:
  - MUST signal `CoreError.unsupported`.
- If no track is loaded:
  - MUST signal `CoreError.invalidState`.

**Error Cases:**
- Invalid position → `CoreError.invalidArgument`
- Seeking not supported → `CoreError.unsupported`
- No track loaded → `CoreError.invalidState`
- Seek failed → `CoreError.decodeError`

**Thread Safety:** May be called from any thread. Implementations MUST synchronize with decoding.

---

#### 4.2.2.6 `currentTime() -> Double`

- When `state` is `playing`:
  - Returns the current playback position in seconds (continuously advancing).
- When `state` is `paused`:
  - Returns the last known playback position (frozen).
- When `state` is `stopped`:
  - Returns `0`.
- When `state` is `error`:
  - Returns the last known position or `0` (implementation-defined, but MUST be documented).

**Return Value:**
- Range: `[0.0, duration()]`
- Precision: Should reflect actual audio rendering position, not decode position.

**Thread Safety:** Must be safe to call from any thread concurrently.

---

#### 4.2.2.7 `duration() -> Double`

- When a track is loaded:
  - Returns the total duration of the track in seconds.
- When no track is loaded (`state = stopped` and no file loaded):
  - Returns `0`.

**Return Value:**
- Range: `[0.0, infinity)` for finite-length tracks
- May return `INFINITY` for streaming sources (future extension)

**Thread Safety:** Must be safe to call from any thread concurrently.

---

#### 4.2.2.8 `state: PlaybackState`

- Exposes the current playback state as defined in 4.2.1.
- MUST always reflect the last completed operation.
- MUST be updated atomically with respect to other operations.

**Thread Safety:** Must be safe to read from any thread concurrently.

---

### 4.2.3 Reference Interface Shapes

These are non-normative examples showing how the contract can be expressed.

**Swift example:**

```swift
public protocol PlaybackService: AnyObject {
    func load(url: URL) throws
    func play() throws
    func pause() throws
    func stop()
    func seek(to seconds: Double) throws
    
    func currentTime() -> Double
    func duration() -> Double
    var state: PlaybackState { get }
}
```

**C++ example:**

```cpp
class PlaybackService {
public:
    virtual ~PlaybackService() = default;

    virtual void load(const std::string& url) = 0;
    virtual void play() = 0;
    virtual void pause() = 0;
    virtual void stop() = 0;
    virtual void seek(double seconds) = 0;

    virtual double currentTime() const = 0;
    virtual double duration() const = 0;
    virtual PlaybackState state() const = 0;
};
```

Any implementation MUST satisfy the semantics in 4.2.2, regardless of syntax.

---

## 4.3 Relationship to Ports

A `PlaybackService` implementation MUST use only the following Ports:

- **`DecoderPort`** (required) - Decodes audio files to PCM
- **`AudioOutputPort`** (required) - Outputs PCM to audio hardware
- **`ClockPort`** (required) - Provides timing for position tracking
- **`LoggerPort`** (required) - Logs events for debugging
- **`FileAccessPort`** (optional) - May be used for direct file access if needed
- **`TagReaderPort`** (optional) - May be used to expose metadata alongside playback

**Constraints:**

1. `PlaybackService` MUST NOT reference AVFoundation, FFmpeg, PipeWire,
   TagLib, or any other platform-specific APIs directly.

2. `PlaybackService` MUST NOT construct platform adapters directly.
   Platform-specific adapters MUST be provided (injected) by the composition root.

All platform details (AVFoundation, FFmpeg, etc.) MUST be confined to Adapter
implementations of the Ports.

---

## 4.4 Composition / Factory

Concrete service instances are created by a composition root (factory).

Responsibilities of the composition root:

1. Construct platform-specific adapters (e.g. AVFoundation-based, FFmpeg-based).
2. Wire these adapters into a concrete `PlaybackService` implementation that
   depends only on Ports.
3. Expose factory functions such as (examples, non-normative):

**Swift example:**

```swift
public enum CoreFactory {
    public static func makeDefaultPlaybackService() -> PlaybackService {
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
```

**C++ example:**

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
```

The specification does not mandate specific factory names, only that such
factories exist and respect the dependency rules above.

---

## 4.5 State Machine Diagram

```
                    ┌─────────┐
                    │ stopped │ (initial state)
                    └────┬────┘
                         │ load()
                         ▼
                    ┌─────────┐
              ┌────▶│ paused  │◀────┐
              │     └────┬────┘     │
        pause()│         │ play()   │ pause()
              │         ▼           │
              │     ┌─────────┐     │
              └─────│ playing │─────┘
                    └────┬────┘
                         │ stop()
                         ▼
                    ┌─────────┐
                    │ stopped │
                    └─────────┘
                    
                         ┌─────────┐
              (any) ────▶│ error   │
                         └─────────┘
                              │ load() (recovery)
                              ▼
                         ┌─────────┐
                         │ paused  │
                         └─────────┘
```

**Notes:**
- `seek()` can be called in any state where a track is loaded (paused/playing), does not change state
- `stop()` is idempotent (can be called from stopped state)
- `play()` and `pause()` are idempotent (no-op if already in target state)
- `buffering` state (if used) is a transient state between paused/playing

---

## 4.6 Error Handling Strategy

Services MUST handle errors according to these principles:

1. **Graceful Degradation**  
   Errors SHOULD NOT crash the application. Set `state = error(...)` and allow recovery.

2. **Clear Error Messages**  
   All `CoreError` values MUST include descriptive messages for debugging.

3. **Recovery Support**  
   After entering `error` state, calling `load()` with a valid file SHOULD allow recovery.

4. **Thread Safety**  
   Error handling MUST be thread-safe. Errors may originate from any thread (e.g., audio callback, decoder thread).

---

## 4.7 Performance Considerations

### Real-Time Audio Thread

- `AudioOutputPort.render()` is called from a real-time audio thread.
- Services MUST ensure the audio callback remains real-time safe:
  - No memory allocations
  - No blocking operations
  - No lock contention
  - Use lock-free queues for inter-thread communication

### Decoder Threading

- Decoding SHOULD occur on a background thread to avoid blocking the audio thread.
- Services SHOULD maintain a decode-ahead buffer to prevent underruns.
- Buffer size SHOULD be configurable (e.g., 2-5 seconds of audio).

### Position Tracking

- `currentTime()` SHOULD reflect actual render position, not decode position.
- Use `ClockPort` for accurate timing measurements.

---

## 4.8 Future Services (Reserved)

The following services are candidates for future specifications.
They are NOT required for the current version, but any future definition
MUST follow the same principles (cross-platform, ports-driven, testable):

### LibraryService
- Library scanning, indexing, and queries
- Persistent metadata cache
- Search and filtering

### TagEditingService
- Cross-platform metadata editing using `TagWriterPort`
- Batch editing operations
- Undo/redo support

### QueueService
- Playlist / playback queue management
- Shuffle and repeat modes
- Queue persistence

### SearchService
- Full-text search across library and metadata
- Advanced filtering
- Search result ranking

### EqualizerService
- Real-time audio effects
- Preset management
- Per-track EQ settings

Each future Service MUST:

1. Be defined in its own numbered spec document.
2. Depend only on Ports and Models.
3. Be implementable on all supported platforms with equivalent semantics.
4. Include comprehensive behavior tests.

---

## 4.9 Testing Requirements

All `PlaybackService` implementations MUST pass the following test categories:

### State Transition Tests
- Verify all valid state transitions work correctly
- Verify idempotent operations remain idempotent
- Verify invalid transitions throw appropriate errors

### Playback Tests
- Load and play various audio formats
- Verify audio output matches expected waveform (±1 sample tolerance)
- Verify position tracking accuracy
- Verify seek accuracy

### Error Handling Tests
- Missing file → `CoreError.notFound`
- Unsupported format → `CoreError.unsupported`
- Corrupted file → `CoreError.decodeError`
- Recovery after error state

### Thread Safety Tests
- Concurrent calls from multiple threads
- No race conditions or deadlocks
- Consistent state under concurrent access

### Performance Tests
- Audio callback real-time safety
- Memory usage stability
- CPU usage within acceptable limits