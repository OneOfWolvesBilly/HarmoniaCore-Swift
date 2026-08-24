//
//  AudioRoutePort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Reads the identity of the audio output device the system currently
//  routes sound to.
//
//  Application-facing: no service consumes this port. Its purpose is to let
//  the application name the destination in a resume prompt ("Continue on
//  MacBook Pro Speakers?") after an output invalidation, before it calls
//  PlaybackService.play().
//
public protocol AudioRoutePort: AnyObject {

    /// The device the system would route new audio output to at the moment
    /// of the call — the system default output / current route — or `nil`
    /// when it cannot be determined.
    ///
    /// Never throws: inability to name the device is not an error the caller
    /// can act on. The result is a snapshot and can be stale by the time it
    /// is used; implementations query the platform on every call and cache
    /// nothing. Observing route *changes* is not part of this contract —
    /// the invalidation signal on `AudioOutputPort` covers the case playback
    /// cares about.
    ///
    /// Safe to call from any thread. NOT real-time safe (may call blocking
    /// platform APIs) — must not be called from the render path.
    func currentOutputDevice() -> AudioOutputDevice?
}
