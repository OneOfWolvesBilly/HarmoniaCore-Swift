//
//  DefaultPlaybackService.swift
//  HarmoniaCore / Services
//
//  SPDX-License-Identifier: MIT
//
//  Default implementation of PlaybackService using dependency injection.
//

import Foundation

public final class DefaultPlaybackService: PlaybackService {
    
    // MARK: - Dependencies (Ports)
    
    private let decoder: DecoderPort
    private let audio: AudioOutputPort
    private let clock: ClockPort
    private let logger: LoggerPort
    
    // MARK: - Internal State
    
    private var currentHandle: DecodeHandle?
    private var streamInfo: StreamInfo?
    private var _state: PlaybackState = .stopped
    private var playbackStartTime: UInt64 = 0
    private var lastKnownPosition: Double = 0
    
    private let lock = NSLock()
    private var isPlaybackLoopRunning = false
    
    // MARK: - Public Interface
    
    public var state: PlaybackState {
        lock.withLock { _state }
    }
    
    public init(
        decoder: DecoderPort,
        audio: AudioOutputPort,
        clock: ClockPort,
        logger: LoggerPort
    ) {
        self.decoder = decoder
        self.audio = audio
        self.clock = clock
        self.logger = logger
    }
    
    // MARK: - PlaybackService Implementation
    
    public func load(url: URL) throws {
        logger.info("Loading: \(url.lastPathComponent)")
        
        return try lock.withLock {
            // Clean up previous track
            cleanupCurrentTrack()
            
            do {
                // Open decoder
                let handle = try decoder.open(url: url)
                let info = try decoder.info(handle)
                
                // Validate stream info
                try info.validate()
                
                // Configure audio output
                try audio.configure(
                    sampleRate: info.sampleRate,
                    channels: info.channels,
                    framesPerBuffer: 512
                )
                
                // Update state
                currentHandle = handle
                streamInfo = info
                lastKnownPosition = 0
                _state = .paused
                
                logger.info("Loaded: \(info.duration)s, \(info.sampleRate)Hz, \(info.channels)ch")
                
            } catch let error as CoreError {
                _state = .error(error)
                throw error
            } catch {
                let coreError = CoreError.ioError(underlying: error)
                _state = .error(coreError)
                throw coreError
            }
        }
    }
    
    public func play() throws {
        try lock.withLock {
            guard let handle = currentHandle else {
                throw CoreError.invalidState("No track loaded. Call load() first.")
            }
            
            // Idempotent: already playing
            guard _state != .playing else {
                return
            }
            
            do {
                // Start audio output
                try audio.start()
                
                // Update state
                _state = .playing
                playbackStartTime = clock.now()
                
                logger.info("Playing")
                
            } catch let error as CoreError {
                _state = .error(error)
                throw error
            } catch {
                let coreError = CoreError.ioError(underlying: error)
                _state = .error(coreError)
                throw coreError
            }
        }
        
        // Start playback loop outside of lock
        startPlaybackLoop()
    }
    
    public func pause() {
        lock.withLock {
            // Idempotent: already paused or stopped
            guard _state == .playing else {
                return
            }
            
            // Update last known position before pausing
            lastKnownPosition = calculateCurrentPosition()
            
            // Stop audio output
            audio.stop()
            
            _state = .paused
            logger.info("Paused at \(lastKnownPosition)s")
        }
    }
    
    public func stop() {
        lock.withLock {
            // Idempotent: already stopped
            guard _state != .stopped else {
                return
            }
            
            // Stop audio output
            audio.stop()
            
            // Clean up
            cleanupCurrentTrack()
            
            _state = .stopped
            logger.info("Stopped")
        }
    }
    
    public func seek(to seconds: Double) throws {
        try lock.withLock {
            guard let handle = currentHandle else {
                throw CoreError.invalidState("No track loaded")
            }
            
            guard let info = streamInfo else {
                throw CoreError.invalidState("No stream info available")
            }
            
            guard seconds >= 0 else {
                throw CoreError.invalidArgument("Seek position must be >= 0, got \(seconds)")
            }
            
            guard seconds <= info.duration else {
                throw CoreError.invalidArgument("Seek position \(seconds)s exceeds duration \(info.duration)s")
            }
            
            do {
                try decoder.seek(handle, toSeconds: seconds)
                lastKnownPosition = seconds
                
                // Reset playback start time if playing
                if _state == .playing {
                    playbackStartTime = clock.now()
                }
                
                logger.info("Seeked to \(seconds)s")
                
            } catch let error as CoreError {
                throw error
            } catch {
                throw CoreError.ioError(underlying: error)
            }
        }
    }
    
    public func currentTime() -> Double {
        lock.withLock {
            return calculateCurrentPosition()
        }
    }
    
    public func duration() -> Double {
        lock.withLock {
            return streamInfo?.duration ?? 0.0
        }
    }
    
    // MARK: - Private Helpers
    
    private func calculateCurrentPosition() -> Double {
        switch _state {
        case .playing:
            let elapsed = Double(clock.now() - playbackStartTime) / 1_000_000_000.0
            return lastKnownPosition + elapsed
        case .paused, .buffering:
            return lastKnownPosition
        case .stopped, .error:
            return 0.0
        }
    }
    
    private func cleanupCurrentTrack() {
        if let handle = currentHandle {
            decoder.close(handle)
            currentHandle = nil
        }
        streamInfo = nil
        lastKnownPosition = 0
    }
    
    private func startPlaybackLoop() {
        // Prevent multiple playback loops
        guard !isPlaybackLoopRunning else { return }
        
        isPlaybackLoopRunning = true
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let bufferSize = 4096 // frames
            let channelCount = self.lock.withLock { self.streamInfo?.channels ?? 2 }
            var buffer = [Float](repeating: 0, count: bufferSize * channelCount)
            
            while true {
                // Check if we should continue
                let (shouldContinue, handle) = self.lock.withLock { () -> (Bool, DecodeHandle?) in
                    guard self._state == .playing, let h = self.currentHandle else {
                        self.isPlaybackLoopRunning = false
                        return (false, nil)
                    }
                    return (true, h)
                }
                
                guard shouldContinue, let handle = handle else {
                    break
                }
                
                do {
                    // Decode frames
                    let framesRead = try buffer.withUnsafeMutableBufferPointer { ptr in
                        try self.decoder.read(
                            handle,
                            into: ptr.baseAddress!,
                            maxFrames: bufferSize
                        )
                    }
                    
                    guard framesRead > 0 else {
                        // End of stream
                        self.logger.info("Playback completed")
                        self.lock.withLock {
                            self.audio.stop()
                            self._state = .stopped
                            self.isPlaybackLoopRunning = false
                        }
                        break
                    }
                    
                    // Render to audio output
                    _ = try buffer.withUnsafeBufferPointer { ptr in
                        try self.audio.render(ptr.baseAddress!, frameCount: framesRead)
                    }
                    
                } catch let error as CoreError {
                    self.logger.error("Playback error: \(error)")
                    self.lock.withLock {
                        self.audio.stop()
                        self._state = .error(error)
                        self.isPlaybackLoopRunning = false
                    }
                    
                    // ✅ FIXED: Add delay to prevent busy loop on repeated errors
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    break
                    
                } catch {
                    let coreError = CoreError.decodeError("Unexpected error: \(error)")
                    self.logger.error("Playback error: \(coreError)")
                    self.lock.withLock {
                        self.audio.stop()
                        self._state = .error(coreError)
                        self.isPlaybackLoopRunning = false
                    }
                    
                    // ✅ FIXED: Add delay to prevent busy loop on repeated errors
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    break
                }
            }
        }
    }
}
