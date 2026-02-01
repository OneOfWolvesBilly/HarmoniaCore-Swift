//
//  StreamInfoTests.swift
//  HarmoniaCoreTests / Models
//
//  SPDX-License-Identifier: MIT
//
//  Tests for StreamInfo model.
//

import XCTest
@testable import HarmoniaCore

final class StreamInfoTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: 44100.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertEqual(info.duration, 180.5)
        XCTAssertEqual(info.sampleRate, 44100.0)
        XCTAssertEqual(info.channels, 2)
        XCTAssertEqual(info.bitDepth, 16)
    }
    
    // MARK: - Validation Tests
    
    func testValidation_ValidInfo() throws {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: 44100.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertNoThrow(try info.validate())
    }
    
    func testValidation_NegativeDuration_Throws() {
        let info = StreamInfo(
            duration: -1.0,
            sampleRate: 44100.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testValidation_ZeroSampleRate_Throws() {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: 0.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testValidation_NegativeSampleRate_Throws() {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: -44100.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testValidation_ZeroChannels_Throws() {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: 44100.0,
            channels: 0,
            bitDepth: 16
        )
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    func testValidation_InvalidBitDepth_Throws() {
        let info = StreamInfo(
            duration: 180.5,
            sampleRate: 44100.0,
            channels: 2,
            bitDepth: 4  // Less than 8
        )
        
        XCTAssertThrowsError(try info.validate()) { error in
            guard case CoreError.invalidArgument = error else {
                XCTFail("Expected .invalidArgument error")
                return
            }
        }
    }
    
    // MARK: - Common Formats Tests
    
    func testCommonFormat_CD_Quality() throws {
        let info = StreamInfo(
            duration: 180.0,
            sampleRate: 44100.0,
            channels: 2,
            bitDepth: 16
        )
        
        XCTAssertNoThrow(try info.validate())
    }
    
    func testCommonFormat_DVD_Quality() throws {
        let info = StreamInfo(
            duration: 180.0,
            sampleRate: 48000.0,
            channels: 2,
            bitDepth: 24
        )
        
        XCTAssertNoThrow(try info.validate())
    }
    
    func testCommonFormat_HiRes_96k() throws {
        let info = StreamInfo(
            duration: 180.0,
            sampleRate: 96000.0,
            channels: 2,
            bitDepth: 24
        )
        
        XCTAssertNoThrow(try info.validate())
    }
    
    func testCommonFormat_HiRes_192k() throws {
        let info = StreamInfo(
            duration: 180.0,
            sampleRate: 192000.0,
            channels: 2,
            bitDepth: 24
        )
        
        XCTAssertNoThrow(try info.validate())
    }
    
    // MARK: - Equatable Tests
    
    func testEquatable_EqualInfo() {
        let info1 = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        let info2 = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        
        XCTAssertEqual(info1, info2)
    }
    
    func testEquatable_DifferentDuration() {
        let info1 = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        let info2 = StreamInfo(duration: 200.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        
        XCTAssertNotEqual(info1, info2)
    }
    
    func testEquatable_DifferentSampleRate() {
        let info1 = StreamInfo(duration: 180.0, sampleRate: 44100.0, channels: 2, bitDepth: 16)
        let info2 = StreamInfo(duration: 180.0, sampleRate: 48000.0, channels: 2, bitDepth: 16)
        
        XCTAssertNotEqual(info1, info2)
    }
}
