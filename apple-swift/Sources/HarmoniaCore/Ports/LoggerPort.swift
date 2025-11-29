//
//  LoggerPort.swift
//  HarmoniaCore / Ports
//
//  SPDX-License-Identifier: MIT
//
//  Defines the logging abstraction used by core services and adapters.
//
public protocol LoggerPort: Sendable {
    func debug(_ msg: @autoclosure () -> String)
    func info(_ msg: @autoclosure () -> String)
    func warn(_ msg: @autoclosure () -> String)
    func error(_ msg: @autoclosure () -> String)
}
