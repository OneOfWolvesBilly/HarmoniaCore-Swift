# HarmoniaCore Architecture

## 1. System Overview

HarmoniaCore is a cross-platform audio framework providing identical behavior on Apple (Swift) and Linux (C++20) platforms.  
It defines a shared architecture centered on **Ports**, **Services**, and **Adapters** — separating abstract logic from platform implementation.

```
Core layers (Dependency View):
+-----------------------------+
|  Applications / UI Clients  |
+-------------+---------------+
              |
              v
+-----------------------------+
|        Services Layer       |  → PlaybackService, LibraryService, TagService
+-------------+---------------+
              |
              v
+-----------------------------+
|          Ports Layer        |  → AudioOutputPort, DecoderPort, TagReaderPort, ...
+-------------+---------------+
              |
              v
+-----------------------------+
|        Adapters Layer       |  → AVFoundation / PipeWire / TagLib
+-------------+---------------+
              |
              v
+-----------------------------+
|   System APIs / Hardware    |
+-----------------------------+
```

---

## 2. Core Layer Responsibilities

| Layer | Responsibility | Examples |
|-------|----------------|-----------|
| **Services** | Implements playback, metadata, and library logic using Ports | `PlaybackService.play()`, `TagService.read()` |
| **Ports** | Defines abstract interfaces for I/O and timing | `AudioOutputPort`, `DecoderPort`, `ClockPort` |
| **Adapters** | Implements Ports using platform APIs | `AVAudioEngineOutputAdapter`, `PipeWireOutputAdapter` |
| **Models** | Simple cross-platform data structures | `StreamInfo`, `TagBundle`, `CoreError` |
| **Utils** | Shared helpers (math, time, string) | `TimeFormatter`, `ErrorMapper` |

### Dependency Direction

- `Services → Ports, Models`  
- `Ports → Models`  
- `Adapters → Ports, Models, platform APIs`  
- `UI / Apps → Services, Ports`

---

## 3. Language and Naming Conventions

HarmoniaCore implements identical specifications in Swift and C++20,  
ensuring idiomatic syntax and memory management per platform while maintaining observable behavior parity.

| Layer | Apple (Swift) | Linux (C++20) |
|-------|----------------|---------------|
| Architecture | Modular package (SPM) | CMake-based project |
| API surface | Protocol-oriented (`protocol`, `struct`) | Class-based (`class`, pure virtual`) |
| Naming style | `PascalCase` types, `camelCase` methods | `PascalCase` types, `snake_case` members |
| Error handling | `throws` / `try` | `try` / `catch` or `std::error_code` |
| Memory model | ARC | RAII (`std::unique_ptr`, `std::shared_ptr`) |
| Asynchrony | `async/await` | `std::thread`, `std::future` |
| Documentation | SwiftDoc (`///`) | Doxygen (`/** */`) |

All platform-independent specifications (`03_ports.md`, `04_services.md`, `05_models.md`)  
are written in a neutral form and implemented idiomatically while preserving identical semantics,  
as defined in `api-parity.md`.

---

## 4. Data Flow Overview

```
Track → DecoderPort → AudioOutputPort → System Audio Device
                    ↘ TagReaderPort → Metadata UI
```

- **PlaybackService** coordinates decoding and output.  
- **DecoderPort** produces PCM frames.  
- **AudioOutputPort** delivers frames to the hardware layer.  
- **ClockPort** tracks playback position.  
- **LoggerPort** records events for parity validation.

---

## 5. Error and Thread Model

| Concern | Description |
|----------|-------------|
| **Error propagation** | All recoverable errors use `CoreError` enumeration (cross-platform). See [Error Mapping Rules](#error-mapping-rules). |
| **Threading model** | Services are thread-safe; decoding and rendering may run on worker threads. All Ports MUST be safe to call from any thread unless explicitly documented otherwise. |
| **Timing consistency** | All timestamps use `ClockPort.now()` for deterministic results. Clock precision MUST be nanosecond or better. |

### Error Mapping Rules

All platform-specific errors MUST be mapped to `CoreError` categories according to these rules:

| Source Error Type | Target CoreError | Mapping Rule |
|-------------------|------------------|--------------|
| File not found | `notFound(description)` | Include file path in description |
| Permission denied | `ioError(underlying)` | Wrap original error for debugging |
| Invalid parameter | `invalidArgument(description)` | Describe which parameter was invalid |
| Codec not supported | `unsupported(description)` | Specify codec/format name |
| Decode failure | `decodeError(description)` | Include frame/position if available |
| Invalid state transition | `invalidState(description)` | Describe expected vs actual state |

**Platform-Specific Guidelines:**

**Swift (Apple):**
```swift
// AVFoundation errors → CoreError
catch let error as NSError {
    switch error.code {
    case AVError.fileNotFound.rawValue:
        throw CoreError.notFound("File not found: \(url)")
    case AVError.unsupportedOutputSettings.rawValue:
        throw CoreError.unsupported("Output format not supported")
    default:
        throw CoreError.ioError(underlying: error)
    }
}
```

**C++ (Linux):**
```cpp
// errno values → CoreError
if (result < 0) {
    switch (errno) {
        case ENOENT:
            throw CoreError::NotFound("File not found: " + path);
        case EACCES:
            throw CoreError::IoError("Permission denied: " + path);
        default:
            throw CoreError::IoError("I/O error: " + std::strerror(errno));
    }
}
```

**Unknown Errors:**
- MUST be wrapped as `ioError` with a descriptive message
- MUST include platform error code if available
- MUST NOT expose platform-specific types in the message

### Thread Safety Requirements

| Component | Thread Safety Guarantee |
|-----------|-------------------------|
| **All Ports** | MUST be safe to call from any thread |
| **Services** | MUST be thread-safe for all public methods |
| **Adapters** | MUST handle concurrent access to shared resources |
| **Models** | MUST be immutable or provide synchronization |

**Specific Requirements:**

1. **FileAccessPort:**
   - MUST handle concurrent reads from different threads
   - File handles MUST be thread-local or properly synchronized
   - MUST handle `EINTR` retries gracefully (POSIX)

2. **DecoderPort:**
   - MUST support decoding on background threads
   - Seek operations MUST be atomic
   - MUST protect internal state with appropriate synchronization

3. **AudioOutputPort:**
   - Render callback MUST be real-time safe
   - MUST NOT block or allocate memory in render path
   - State changes MUST be lock-free or use wait-free queues

4. **ClockPort:**
   - MUST provide monotonic time across all threads
   - MUST NOT require synchronization for read-only operations

---

## 6. Extensibility & Plugin Design

Future versions of HarmoniaCore will support third-party Adapters and Services via a **Plugin Registry**.

| Plugin Type | Purpose | Example |
|--------------|----------|----------|
| `AudioEffectPlugin` | Real-time effects or filters | Equalizer, Reverb |
| `DecoderPlugin` | New codec decoders | Opus, Vorbis, APE |

All plugins must conform to defined protocols,  
validated at runtime to ensure compatibility and deterministic behavior across platforms.

---

## 7. Testing & Validation Overview

Every implementation must pass **behavior-parity tests** between Swift and C++20 versions.

- Frame-by-frame waveform comparison (±1 sample tolerance)  
- Metadata extraction consistency  
- File load/unload parity  
- Unified CI using **GitHub Actions** (macOS & Linux runners)  
- Reproducible logs for each parity test run

---

## 8. Documentation Map

### Core Specifications

| File | Purpose |
|------|----------|
| `docs/specs/01_architecture.md` | System architecture overview (this file) |
| `docs/specs/02_adapters.md` | Adapter specification (platform-agnostic) |
| `docs/specs/02_01_apple.adapters.md` | Apple-specific adapters |
| `docs/specs/02_02_linux.adapters.md` | Linux-specific adapters |
| `docs/specs/03_ports.md` | Interface definitions |
| `docs/specs/04_services.md` | Public service APIs |
| `docs/specs/05_models.md` | Shared data models |

### Extended Specifications

| File | Purpose |
|------|----------|
| `docs/specs/api-parity.md` | Behavior contract between Swift and C++ implementations |
| `docs/specs/behavior-flow.md` | Runtime and data flow diagram |
| `docs/specs/testing-strategy.md` | CI parity validation procedures |