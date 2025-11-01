# Harmonia Core

**HarmoniaCore** is a dual-implementation audio framework that defines an open behavior specification for local-audio applications.  
Part of the [**HarmoniaSuite**](https://github.com/OneOfWolvesBilly/HarmoniaSuite) ecosystem.

- **Swift (Apple):** AVFoundation + async/await  
- **C++20 (Linux):** PipeWire / ALSA + CMake build system  
- **No shared code or ABI**, only shared functional behavior defined in [`docs/api-parity.md`](./docs/api-parity.md)

---

## 🎯 Goal
To demonstrate that identical audio framework behavior can exist natively across ecosystems without cross-language bindings,  
while maintaining strict behavior parity between Apple (Swift) and Linux (C++20) implementations.

---

## 🧱 Platform Responsibility Separation

| Layer | Apple (Swift) | Linux (C++20) |
|--------|----------------|----------------|
| **Core** | HarmoniaCore (Swift / AVFoundation) | HarmoniaCore (C++20 / PipeWire, planned 2026) |
| **Application** | HarmoniaPlayer (macOS / iOS) | *(Optional future project: HarmoniaPlayer_Linux)* |

> **HarmoniaCore** focuses solely on the framework and behavior specification layer.  
> Platform applications such as HarmoniaPlayer are implemented independently and are not part of this repository.

---

## 📂 Structure
```
HarmoniaCore/
├─ apple-swift/      # Swift Package (AVFoundation)
├─ linux-cpp/        # C++20 Implementation (PipeWire / ALSA, CMake)
├─ docs/
│  └─ api-parity.md  # Behavior specification
└─ test-vectors/
   └─ audio/         # Shared validation files
```

---

## 🧪 Parity Verification
| Platform | Command | Output |
|-----------|----------|--------|
| macOS (Swift) | `xcodebuild test` | Waveform checksum + timing log |
| Linux (C++20) | `cmake && ctest` | Identical checksum expected |

> The Linux implementation is scheduled for **2026**, with functional parity validated through shared audio test vectors  
> and behavior constraints defined in [`docs/api-parity.md`](./docs/api-parity.md).

---

## 🪪 License
MIT © 2025 Chih-hao (Billy) Chen  
Contact → harmonia.audio.project@gmail.com
