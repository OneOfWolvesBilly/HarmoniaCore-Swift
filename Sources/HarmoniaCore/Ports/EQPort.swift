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
//  EQPort is the abstract pluggable EQ node that exposes the runtime
//  control surface (enable, preamp, per-band gain) consumed by
//  PlaybackService implementations.
//
//  Graph wiring — attaching the EQ DSP node into a concrete audio
//  engine — is the responsibility of the platform adapter that owns
//  the engine, not of the Port. The Port stays platform-agnostic.
//
//  All gain values are expressed in decibels.
//

public protocol EQPort: AnyObject {

    /// Whether EQ processing is active. When `false`, the node passes
    /// audio through unchanged regardless of band or preamp values.
    var isEnabled: Bool { get set }

    /// Master preamp gain in dB, applied after band processing.
    /// Implementations clamp out-of-range writes to ±12 dB.
    var preamp: Float { get set }

    /// Per-band gain values in dB. The array length is fixed at 10.
    /// Implementations clamp out-of-range writes to ±12 dB per band.
    var bandGains: [Float] { get set }
}
