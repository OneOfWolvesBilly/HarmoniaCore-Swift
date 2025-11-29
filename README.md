# HarmoniaCore

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013+%20%7C%20iOS%2016+-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Cross-platform audio playback framework for Swift (Apple platforms) and C++20 (Linux).

## Overview

HarmoniaCore provides a clean, testable audio playback API following hexagonal architecture principles. The same service interfaces work identically across platforms, with platform-specific implementations hidden behind abstract Port interfaces.

**Current Status**: Swift implementation complete (v0.1) • Linux implementation planned (v0.2)

## Quick Start

### Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/HarmoniaCore.git", from: "0.1.0")
]
```

### Basic Usage

```swift
import HarmoniaCore

// Create service
let service = DefaultPlaybackService(
    decoder: AVAssetReaderDecoderAdapter(logger: OSLogAdapter()),
    audio: AVAudioEngineOutputAdapter(logger: OSLogAdapter()),
    clock: MonotonicClockAdapter(),
    logger: OSLogAdapter()
)

// Playback control
try service.load(url: audioFileURL)
try service.play()
service.pause()
try service.seek(to: 30.0)
service.stop()

// Query state
print("Duration: \(service.duration())s")
print("Position: \(service.currentTime())s")
print("State: \(service.state)")
```

## Architecture

HarmoniaCore uses **Ports & Adapters** (Hexagonal Architecture):

```
┌───────────────────────┐
│   UI Application      │
└──────────┬────────────┘
           │
┌──────────▼────────────┐
│   Services Layer      │  ◄── PlaybackService (load, play, pause, seek)
└──────────┬────────────┘
           │
┌──────────▼────────────┐
│   Ports Layer         │  ◄── Abstract interfaces (DecoderPort, AudioOutputPort...)
└──────────┬────────────┘
           │
┌──────────▼────────────┐
│   Adapters Layer      │  ◄── Platform implementations (AVFoundation, FFmpeg...)
└───────────────────────┘
```

**Key Benefits**:
- Platform-agnostic business logic
- Fully testable with mock implementations
- Easy to add new platforms or swap implementations

## Implementation Status

| Component | Swift (Apple) | C++20 (Linux) |
|-----------|---------------|---------------|
| Ports (7) | ✅ Complete | 🚧 Planned v0.2 |
| Adapters | ✅ 8 adapters | 🚧 Planned v0.2 |
| Services | ✅ PlaybackService | 🚧 Planned v0.2 |
| Tests | ✅ Full coverage | 🚧 Planned v0.2 |

### Implemented Components

**Ports**: LoggerPort, ClockPort, FileAccessPort, DecoderPort, AudioOutputPort, TagReaderPort, TagWriterPort

**Apple Adapters**: OSLogAdapter, MonotonicClockAdapter, SandboxFileAccessAdapter, AVAssetReaderDecoderAdapter, AVAudioEngineOutputAdapter, AVMetadataTagReaderAdapter, AVMutableTagWriterAdapter, NoopLogger

**Services**: PlaybackService protocol, DefaultPlaybackService implementation

## Documentation

### Specifications (Platform-Agnostic)
- [Architecture Overview](docs/specs/01_architecture.md)
- [Adapters Specification](docs/specs/02_adapters.md)
- [Ports Specification](docs/specs/03_ports.md)
- [Services Specification](docs/specs/04_services.md)
- [Models Specification](docs/specs/05_models.md)

### Implementation Guides
- [Apple Adapters Implementation](docs/impl/02_01_apple_adapters_impl.md)
- [Ports Implementation](docs/impl/03_ports_impl.md)
- [Services Implementation](docs/impl/04_services_impl.md)
- [Models Implementation](docs/impl/05_models_impl.md)

## Development

### Requirements
- Xcode 15.0+ (Swift 5.9+)
- macOS 13.0+ or iOS 16.0+

### Building & Testing

```bash
# Build
swift build

# Run tests
swift test

# Release build
swift build -c release
```

### Testing with Mocks

```swift
let mockDecoder = MockDecoderPort()
let mockAudio = MockAudioOutputPort()

let service = DefaultPlaybackService(
    decoder: mockDecoder,
    audio: mockAudio,
    clock: MockClockPort(),
    logger: NoopLogger()
)

try service.load(url: testURL)
XCTAssertTrue(mockDecoder.openCalled)
```

## Roadmap

### v0.1 - Swift Implementation ✅ (Current)
- [x] Core architecture
- [x] All ports and adapters
- [x] PlaybackService
- [x] Comprehensive tests

### v0.2 - Linux Implementation (Q2 2025)
- [ ] C++20 port interfaces
- [ ] FFmpeg/PipeWire adapters
- [ ] Cross-platform parity tests

### v0.3+ - Advanced Features
- [ ] Gapless playback
- [ ] Real-time equalizer
- [ ] Playlist service
- [ ] Hi-Res audio support

## Contributing

Contributions welcome! Please:

1. Follow the hexagonal architecture (Ports for abstractions, Adapters for implementations)
2. Write tests for all new code
3. Update relevant documentation
4. Use conventional commit messages

See the specification documents for detailed design guidelines.

## License

MIT License - see [LICENSE.md](LICENSE.md) for details.

Copyright (c) 2025 Chih-hao (Billy) Chen

## Contact

- GitHub: [@YOUR_USERNAME](https://github.com/YOUR_USERNAME)
- Project: [HarmoniaCore](https://github.com/YOUR_USERNAME/HarmoniaCore)

---

**Building a music player?** Check out [HarmoniaPlayer](https://github.com/YOUR_USERNAME/HarmoniaPlayer) - a reference SwiftUI app using HarmoniaCore.