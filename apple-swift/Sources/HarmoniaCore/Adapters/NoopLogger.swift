//
//  NoopLogger.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements LoggerPort as a no-op logger for tests and benchmarks.
//
public struct NoopLogger: LoggerPort {
    public init() {}

    public func debug(_ message: @autoclosure () -> String) {}
    public func info(_ message: @autoclosure () -> String) {}
    public func warn(_ message: @autoclosure () -> String) {}
    public func error(_ message: @autoclosure () -> String) {}
}
