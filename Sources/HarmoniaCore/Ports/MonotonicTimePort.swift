//
//  MonotonicTimePort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Provides monotonic time source abstraction for scheduling and drift calculations.
//

/// Protocol for accessing monotonic system time.
///
/// Provides nanosecond-precision monotonic time that is not affected by
/// wall-clock adjustments (e.g., NTP, daylight saving, user changes).
///
/// Thread Safety: Must be safe to call from any thread without synchronization.
/// Real-Time Safety: Should be safe to call from real-time audio threads.
public protocol MonotonicTimePort: Sendable {
    
    /// Returns monotonic time in nanoseconds since an unspecified epoch.
    ///
    /// The returned value is guaranteed to be monotonically increasing
    /// (never goes backwards), even across system sleep/wake cycles.
    ///
    /// Only relative differences between calls are meaningful; the absolute
    /// value and epoch are implementation-defined.
    ///
    /// - Returns: Monotonic time in nanoseconds
    ///
    /// # Example
    /// ```swift
    /// let time: MonotonicTimePort = MonotonicTimeAdapter()
    /// let start = time.now()
    /// // ... perform operation ...
    /// let elapsed = time.now() - start
    /// print("Operation took \(elapsed) nanoseconds")
    /// ```
    func now() -> UInt64
}
