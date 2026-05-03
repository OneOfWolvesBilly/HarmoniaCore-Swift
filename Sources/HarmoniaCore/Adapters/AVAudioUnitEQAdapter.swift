//
//  AVAudioUnitEQAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Apple-platform EQPort implementation backed by AVAudioUnitEQ.
//  Slice 9-K: 10-band graphic EQ.
//
//  CONFIGURATION (per spec §9-K)
//  -----------------------------
//  - numberOfBands: 10
//  - centre frequencies (Hz): 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
//  - filterType per band: .parametric
//  - bandwidth: 2.0 octaves per band
//    (spec expresses this as Q = 0.7071 / Butterworth — bandwidth in
//    octaves on AVAudioUnitEQFilterParameters is the equivalent
//    representation: BW(octaves) ≈ 2 * asinh(1 / (2 * Q)) / ln(2),
//    Q = 0.7071 → BW ≈ 2.0 octaves)
//  - per-band gain clamping: ±12 dB
//  - preamp clamping: ±12 dB (mapped to AVAudioUnitEQ.globalGain)
//  - default state: bypassed (isEnabled = false), all bands flat,
//    preamp 0
//

import AVFoundation

public final class AVAudioUnitEQAdapter: EQPort {

    // MARK: - Constants

    /// Centre frequencies in Hz, ordered from low to high.
    /// 10-band graphic EQ following the macOS Music.app convention.
    private static let centreFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    /// Bandwidth in octaves applied to every parametric band.
    /// Equivalent to Butterworth Q ≈ 0.7071 (see file header).
    private static let bandwidthOctaves: Float = 2.0

    /// Gain limits (dB) for both per-band gain and preamp.
    private static let gainLowerBound: Float = -12
    private static let gainUpperBound: Float = 12

    // MARK: - State

    private let eq: AVAudioUnitEQ

    // MARK: - Init

    public init() {
        let eq = AVAudioUnitEQ(numberOfBands: Self.centreFrequencies.count)
        // Default to bypassed; isEnabled getter returns !bypass.
        eq.bypass = true
        eq.globalGain = 0

        for (index, frequency) in Self.centreFrequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = Self.bandwidthOctaves
            band.gain = 0
            band.bypass = false
        }

        self.eq = eq
    }

    // MARK: - EQPort

    public var isEnabled: Bool {
        get { !eq.bypass }
        set { eq.bypass = !newValue }
    }

    public var preamp: Float {
        get { eq.globalGain }
        set { eq.globalGain = Self.clamp(newValue) }
    }

    public var bandGains: [Float] {
        get { eq.bands.map { $0.gain } }
        set {
            // Tolerate length mismatch by using min(count, bands.count);
            // missing entries leave the existing gain untouched, surplus
            // entries are ignored.
            let count = min(newValue.count, eq.bands.count)
            for i in 0..<count {
                eq.bands[i].gain = Self.clamp(newValue[i])
            }
        }
    }

    /// Wires the EQ as a full chain segment: previous → eq → next.
    /// Any pre-existing `previous → next` connection is replaced.
    public func attach(to engine: AVAudioEngine,
                       between previous: AVAudioNode,
                       and next: AVAudioNode,
                       format: AVAudioFormat?) throws {
        engine.attach(eq)
        // Tear down whatever previous was connected to (typically `next`
        // directly) so we can splice the EQ node into the segment.
        engine.disconnectNodeOutput(previous)
        engine.connect(previous, to: eq,   format: format)
        engine.connect(eq,       to: next, format: format)
    }

    // MARK: - Private helpers

    private static func clamp(_ value: Float) -> Float {
        return min(gainUpperBound, max(gainLowerBound, value))
    }
}
