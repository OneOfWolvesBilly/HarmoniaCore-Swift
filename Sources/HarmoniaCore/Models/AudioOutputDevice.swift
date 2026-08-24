//
//  AudioOutputDevice.swift
//  HarmoniaCore / Models
//
//  SPDX-License-Identifier: MIT
//
//  Identity of the audio output device the system currently routes sound to.
//  Produced by AudioRoutePort.currentOutputDevice(); consumed by the
//  application layer, typically to name the destination in a resume prompt
//  after an output invalidation.
//

public struct AudioOutputDevice: Sendable, Equatable {

    /// Stable, platform-defined unique identifier for the device.
    ///
    /// Opaque — compare for equality, never parse. Stable across queries
    /// while the device stays connected; not guaranteed stable across
    /// reconnects or reboots.
    public let id: String

    /// Human-readable device name for display (e.g. "MacBook Pro Speakers").
    ///
    /// Passed through from the platform without normalization. Not unique —
    /// two devices may share a name.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
