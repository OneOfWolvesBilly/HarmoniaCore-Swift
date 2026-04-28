//
//  LyricsLanguageVariantTests.swift
//  HarmoniaCoreTests / Models
//
//  SPDX-License-Identifier: MIT
//
//  Tests for LyricsLanguageVariant model (Slice 9-J).
//

import XCTest
@testable import HarmoniaCore

final class LyricsLanguageVariantTests: XCTestCase {

    // MARK: - Initialization

    func testInit_WithLanguageCode_StoresValues() {
        let variant = LyricsLanguageVariant(languageCode: "eng", text: "Hello world")
        XCTAssertEqual(variant.languageCode, "eng")
        XCTAssertEqual(variant.text, "Hello world")
    }

    func testInit_WithNilLanguageCode_StoresNil() {
        let variant = LyricsLanguageVariant(languageCode: nil, text: "undeclared language")
        XCTAssertNil(variant.languageCode)
        XCTAssertEqual(variant.text, "undeclared language")
    }

    func testInit_WithJapaneseText_StoresCorrectly() {
        let variant = LyricsLanguageVariant(languageCode: "jpn", text: "歌詞のテキスト")
        XCTAssertEqual(variant.languageCode, "jpn")
        XCTAssertEqual(variant.text, "歌詞のテキスト")
    }

    // MARK: - Equatable

    func testEquatable_SameValues_AreEqual() {
        let a = LyricsLanguageVariant(languageCode: "eng", text: "Hello")
        let b = LyricsLanguageVariant(languageCode: "eng", text: "Hello")
        XCTAssertEqual(a, b)
    }

    func testEquatable_DifferentText_AreNotEqual() {
        let a = LyricsLanguageVariant(languageCode: "eng", text: "Hello")
        let b = LyricsLanguageVariant(languageCode: "eng", text: "World")
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_DifferentLanguageCode_AreNotEqual() {
        let a = LyricsLanguageVariant(languageCode: "eng", text: "Hello")
        let b = LyricsLanguageVariant(languageCode: "chi", text: "Hello")
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_NilVsNonNilLanguageCode_AreNotEqual() {
        let a = LyricsLanguageVariant(languageCode: nil, text: "Hello")
        let b = LyricsLanguageVariant(languageCode: "eng", text: "Hello")
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_BothNilLanguageCode_SameText_AreEqual() {
        let a = LyricsLanguageVariant(languageCode: nil, text: "Hello")
        let b = LyricsLanguageVariant(languageCode: nil, text: "Hello")
        XCTAssertEqual(a, b)
    }

    // MARK: - Codable

    func testCodable_RoundTrip_WithLanguageCode() throws {
        let original = LyricsLanguageVariant(languageCode: "eng", text: "Round-trip test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LyricsLanguageVariant.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodable_RoundTrip_NilLanguageCode() throws {
        let original = LyricsLanguageVariant(languageCode: nil, text: "No language declared")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LyricsLanguageVariant.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}