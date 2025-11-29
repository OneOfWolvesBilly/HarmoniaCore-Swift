//
//  StreamInfo.swift
//  HarmoniaCore / Models
//
//  SPDX-License-Identifier: MIT
//
//  Describes decoded audio stream properties (duration, sample rate, channels, bit depth).
//  Conforms to specification in docs/specs/05_models.md
//

public struct StreamInfo: Sendable, Equatable {
    public let duration: Double      // seconds
    public let sampleRate: Double    // Hz (e.g., 44100.0, 48000.0)
    public let channels: Int         // typically 1 (mono) or 2 (stereo)
    public let bitDepth: Int         // e.g., 16, 24, 32

    public init(duration: Double, sampleRate: Double, channels: Int, bitDepth: Int) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

// MARK: - Validation

extension StreamInfo {
    /// Validates that all fields are within acceptable ranges
    public func validate() throws {
        guard duration >= 0 else {
            throw CoreError.invalidArgument("Duration must be >= 0, got \(duration)")
        }
        guard sampleRate > 0 else {
            throw CoreError.invalidArgument("Sample rate must be > 0, got \(sampleRate)")
        }
        guard channels >= 1 else {
            throw CoreError.invalidArgument("Channels must be >= 1, got \(channels)")
        }
        guard bitDepth >= 8 else {
            throw CoreError.invalidArgument("Bit depth must be >= 8, got \(bitDepth)")
        }
    }
}
