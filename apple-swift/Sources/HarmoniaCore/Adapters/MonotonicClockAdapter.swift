//
//  MonotonicClockAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements ClockPort using DispatchTime for monotonic nanosecond precision.
//
import Foundation
import Dispatch

public struct MonotonicClockAdapter: ClockPort {
    public init() {}

    public func now() -> UInt64 {
        // Uses DispatchTime.now().uptimeNanoseconds for true monotonic time.
        // This is guaranteed to never go backwards, even across system sleep/wake.
        return DispatchTime.now().uptimeNanoseconds
    }
}
