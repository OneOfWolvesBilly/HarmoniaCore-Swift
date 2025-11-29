//
//  PlaybackService.swift
//  HarmoniaCore / Services
//
//  SPDX-License-Identifier: MIT
//
//  Defines the public playback control interface.
//  Conforms to specification in docs/specs/04_services.md
//

import Foundation

// MARK: - PlaybackState

public enum PlaybackState: Equatable, Sendable {
    case stopped
    case playing
    case paused
    case buffering
    case error(CoreError)
}

extension PlaybackState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stopped: return "stopped"
        case .playing: return "playing"
        case .paused: return "paused"
        case .buffering: return "buffering"
        case .error(let error): return "error(\(error))"
        }
    }
}

// MARK: - PlaybackService Protocol

public protocol PlaybackService: AnyObject {
    /// Current playback state (read-only)
    var state: PlaybackState { get }
    
    /// Loads a track from the given URL
    /// - Throws: CoreError if loading fails
    /// - Postcondition: state == .paused on success
    func load(url: URL) throws
    
    /// Starts playback
    /// - Throws: CoreError.invalidState if no track is loaded
    /// - Postcondition: state == .playing on success
    func play() throws
    
    /// Pauses playback (idempotent)
    /// - Postcondition: state == .paused
    func pause()
    
    /// Stops playback and releases resources (idempotent)
    /// - Postcondition: state == .stopped
    func stop()
    
    /// Seeks to the specified position
    /// - Parameter seconds: Target position in seconds
    /// - Throws: CoreError.invalidArgument if position is invalid
    /// - Throws: CoreError.invalidState if no track is loaded
    func seek(to seconds: Double) throws
    
    /// Returns current playback position in seconds
    /// - Returns: Current position (0.0 if stopped)
    func currentTime() -> Double
    
    /// Returns total duration of loaded track
    /// - Returns: Duration in seconds (0.0 if no track loaded)
    func duration() -> Double
}
