//
//  AVAudioUnitEQAdapterTests.swift
//  HarmoniaCoreTests / Adapters
//
//  SPDX-License-Identifier: MIT
//
//  Slice 9-K: AVAudioUnitEQAdapter unit tests.
//
//  TESTING APPROACH
//  ----------------
//  These tests cover the EQPort control surface only:
//  default state, in-range read/write, and clamping at ±12 dB.
//  They do NOT exercise audio rendering or the attach() chain
//  insertion — that is verified at the playback-service layer
//  (`testPlaybackService_LoadInsertsEQNode` in
//  DefaultPlaybackServiceTests).
//
//  RED PHASE
//  ---------
//  The current `AVAudioUnitEQAdapter` is a stub skeleton; every
//  test in this file is expected to fail until the green phase
//  replaces the skeleton with the real AVAudioUnitEQ-backed
//  implementation.
//

import XCTest
@testable import HarmoniaCore

final class AVAudioUnitEQAdapterTests: XCTestCase {

    // MARK: - Defaults

    func testEQPort_DefaultIsDisabled() {
        let sut = AVAudioUnitEQAdapter()
        XCTAssertFalse(sut.isEnabled,
                       "EQ must be disabled by default")
    }

    func testEQPort_DefaultBandsAreFlat() {
        let sut = AVAudioUnitEQAdapter()
        XCTAssertEqual(sut.bandGains.count, 10,
                       "EQ must expose exactly 10 bands")
        XCTAssertTrue(sut.bandGains.allSatisfy { $0 == 0 },
                      "All bands must be flat (0 dB) by default; got \(sut.bandGains)")
    }

    // MARK: - Updates (in-range)

    func testEQPort_SetBandGain_Updates() {
        let sut = AVAudioUnitEQAdapter()
        sut.bandGains[3] = 6
        XCTAssertEqual(sut.bandGains[3], 6, accuracy: 0.001,
                       "Setting bandGains[3] = 6 must read back as 6")
    }

    func testEQPort_SetPreamp_Updates() {
        let sut = AVAudioUnitEQAdapter()
        sut.preamp = -3
        XCTAssertEqual(sut.preamp, -3, accuracy: 0.001,
                       "Setting preamp = -3 must read back as -3")
    }

    // MARK: - Clamping

    func testEQPort_GainClamping_LowBound() {
        let sut = AVAudioUnitEQAdapter()
        sut.bandGains[0] = -20
        XCTAssertEqual(sut.bandGains[0], -12, accuracy: 0.001,
                       "Setting bandGains[0] = -20 must clamp to -12 dB lower bound")
    }

    func testEQPort_GainClamping_HighBound() {
        let sut = AVAudioUnitEQAdapter()
        sut.preamp = 20
        XCTAssertEqual(sut.preamp, 12, accuracy: 0.001,
                       "Setting preamp = 20 must clamp to +12 dB upper bound")
    }
}
