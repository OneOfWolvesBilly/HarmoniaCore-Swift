//
//  EQPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the equaliser DSP node interface used by playback services.
//
//  PURPOSE
//  -------
//  EQPort is the abstract pluggable EQ node that can be inserted into
//  the audio chain between the decoder and the audio output. It exposes
//  the runtime control surface (enable, preamp, per-band gain) and the
//  one-shot attach call that wires the EQ DSP node into an
//  `AVAudioEngine` graph.
//
//  All gain values are expressed in decibels.
//

import AVFoundation

public protocol EQPort: AnyObject {

    /// Whether EQ processing is active. When `false`, the node passes
    /// audio through unchanged regardless of band or preamp values.
    var isEnabled: Bool { get set }

    /// Master preamp gain in dB, applied after band processing.
    /// Implementations clamp out-of-range writes to ±12 dB.
    var preamp: Float { get set }

    /// Per-band gain values in dB. The array length is fixed at 10
    /// (Slice 9-K). Implementations clamp out-of-range writes to
    /// ±12 dB per band.
    var bandGains: [Float] { get set }

    /// Attaches the EQ node to the engine and inserts it into the
    /// audio chain immediately after `previous`. Must be called once
    /// before audio flows through the chain.
    ///
    /// - Parameters:
    ///   - engine: The `AVAudioEngine` instance owning the audio chain.
    ///   - previous: The node directly upstream of the EQ.
    /// - Throws: An implementation-defined error if attachment fails.
    func attach(to engine: AVAudioEngine, after previous: AVAudioNode) throws
}
