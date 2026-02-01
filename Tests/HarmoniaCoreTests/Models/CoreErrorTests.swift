//
//  CoreErrorTests.swift
//  HarmoniaCoreTests / Models
//
//  SPDX-License-Identifier: MIT
//
//  Tests for CoreError model.
//

import XCTest
@testable import HarmoniaCore

final class CoreErrorTests: XCTestCase {
    
    // MARK: - Error Creation Tests
    
    func testInvalidArgument() {
        let error = CoreError.invalidArgument("Test message")
        
        let description = error.description
        XCTAssertTrue(description.contains("Invalid argument"))
        XCTAssertTrue(description.contains("Test message"))
    }
    
    func testInvalidState() {
        let error = CoreError.invalidState("Test state message")
        
        let description = error.description
        XCTAssertTrue(description.contains("Invalid state"))
        XCTAssertTrue(description.contains("Test state message"))
    }
    
    func testNotFound() {
        let error = CoreError.notFound("File not found: /path/to/file.mp3")
        
        let description = error.description
        XCTAssertTrue(description.contains("Not found"))
        XCTAssertTrue(description.contains("/path/to/file.mp3"))
    }
    
    func testIOError() {
        let underlyingError = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Test error"]
        )
        let error = CoreError.ioError(underlying: underlyingError)
        
        let description = error.description
        XCTAssertTrue(description.contains("I/O error"))
    }
    
    func testDecodeError() {
        let error = CoreError.decodeError("Invalid audio data")
        
        let description = error.description
        XCTAssertTrue(description.contains("Decode error"))
        XCTAssertTrue(description.contains("Invalid audio data"))
    }
    
    func testUnsupported() {
        let error = CoreError.unsupported("FLAC not supported")
        
        let description = error.description
        XCTAssertTrue(description.contains("Unsupported"))
        XCTAssertTrue(description.contains("FLAC"))
    }
    
    // MARK: - Equatable Tests
    
    func testEquatable_SameInvalidArgument() {
        let error1 = CoreError.invalidArgument("Test")
        let error2 = CoreError.invalidArgument("Test")
        
        XCTAssertEqual(error1, error2)
    }
    
    func testEquatable_DifferentInvalidArgument() {
        let error1 = CoreError.invalidArgument("Test 1")
        let error2 = CoreError.invalidArgument("Test 2")
        
        XCTAssertNotEqual(error1, error2)
    }
    
    func testEquatable_DifferentErrorTypes() {
        let error1 = CoreError.invalidArgument("Test")
        let error2 = CoreError.invalidState("Test")
        
        XCTAssertNotEqual(error1, error2)
    }
    
    func testEquatable_IOErrors() {
        // IOErrors are considered equal (underlying not compared)
        let error1 = CoreError.ioError(underlying: NSError(domain: "A", code: 1))
        let error2 = CoreError.ioError(underlying: NSError(domain: "B", code: 2))
        
        XCTAssertEqual(error1, error2)
    }
    
    // MARK: - Throwing and Catching Tests
    
    func testThrowAndCatch_InvalidArgument() {
        XCTAssertThrowsError(try throwInvalidArgument()) { error in
            guard case CoreError.invalidArgument(let message) = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
            XCTAssertEqual(message, "Test invalid argument")
        }
    }
    
    func testThrowAndCatch_NotFound() {
        XCTAssertThrowsError(try throwNotFound()) { error in
            guard case CoreError.notFound = error else {
                XCTFail("Expected .notFound error")
                return
            }
        }
    }
    
    // MARK: - Usage Pattern Tests
    
    func testUsagePattern_FileNotFound() {
        do {
            try simulateFileLoad(fileExists: false)
            XCTFail("Should have thrown error")
        } catch let error as CoreError {
            if case .notFound(let message) = error {
                XCTAssertTrue(message.contains("not found"))
            } else {
                XCTFail("Expected .notFound error")
            }
        } catch {
            XCTFail("Expected CoreError")
        }
    }
    
    func testUsagePattern_InvalidParameter() {
        do {
            try simulateSeek(position: -1.0)
            XCTFail("Should have thrown error")
        } catch let error as CoreError {
            if case .invalidArgument(let message) = error {
                XCTAssertTrue(message.contains("negative"))
            } else {
                XCTFail("Expected .invalidArgument error")
            }
        } catch {
            XCTFail("Expected CoreError")
        }
    }
    
    // MARK: - Helper Functions
    
    private func throwInvalidArgument() throws {
        throw CoreError.invalidArgument("Test invalid argument")
    }
    
    private func throwNotFound() throws {
        throw CoreError.notFound("File not found")
    }
    
    private func simulateFileLoad(fileExists: Bool) throws {
        if !fileExists {
            throw CoreError.notFound("File not found")
        }
    }
    
    private func simulateSeek(position: Double) throws {
        if position < 0 {
            throw CoreError.invalidArgument("Seek position cannot be negative")
        }
    }
}
