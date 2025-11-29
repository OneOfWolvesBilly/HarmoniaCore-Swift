//
//  OSLogAdapter.swift
//  HarmoniaCore / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Implements LoggerPort using Apple's unified logging system (os.Logger).
//

import Foundation
import OSLog

public struct OSLogAdapter: LoggerPort {
    private let logger: Logger

    public init(subsystem: String = "HarmoniaCore", category: String = "Core") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: @autoclosure () -> String) {
        // Need to evaluate the autoclosure immediately to avoid escaping issues
        let msg = message()
        logger.debug("\(msg)")
    }

    public func info(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.info("\(msg)")
    }

    public func warn(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.warning("\(msg)")
    }

    public func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg)")
    }
}
