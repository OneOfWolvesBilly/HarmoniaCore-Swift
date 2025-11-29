//
//  CoreError.swift
//  HarmoniaCore / Models
//
//  SPDX-License-Identifier: MIT
//
//  Defines the shared error types used across ports and adapters.
//  Conforms to specification in docs/specs/05_models.md
//

public enum CoreError: Error, Sendable {
    case invalidArgument(String)
    case invalidState(String)
    case notFound(String)
    case ioError(underlying: Error)
    case decodeError(String)
    case unsupported(String)
}

// MARK: - CustomStringConvertible

extension CoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidArgument(let msg):
            return "Invalid argument: \(msg)"
        case .invalidState(let msg):
            return "Invalid state: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .ioError(let underlying):
            return "I/O error: \(underlying.localizedDescription)"
        case .decodeError(let msg):
            return "Decode error: \(msg)"
        case .unsupported(let msg):
            return "Unsupported: \(msg)"
        }
    }
}

// MARK: - Equatable

extension CoreError: Equatable {
    public static func == (lhs: CoreError, rhs: CoreError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidArgument(let l), .invalidArgument(let r)):
            return l == r
        case (.invalidState(let l), .invalidState(let r)):
            return l == r
        case (.notFound(let l), .notFound(let r)):
            return l == r
        case (.ioError, .ioError):
            // Simplified: underlying errors not compared
            return true
        case (.decodeError(let l), .decodeError(let r)):
            return l == r
        case (.unsupported(let l), .unsupported(let r)):
            return l == r
        default:
            return false
        }
    }
}
