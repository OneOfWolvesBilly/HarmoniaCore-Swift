//
//  LyricsLanguageVariant.swift
//  HarmoniaCore / Models
//
//  SPDX-License-Identifier: MIT
//
//  Represents one language variant of embedded USLT lyrics.
//  Multiple variants may exist in a single audio file (e.g. English + Chinese).
//

import Foundation

/// A single language variant of embedded lyrics (USLT frame).
///
/// A single audio file may contain multiple USLT frames, each carrying lyrics
/// in a different language. Each frame is mapped to one `LyricsLanguageVariant`.
///
/// - `languageCode`: ISO 639-2 three-letter code (e.g. `"eng"`, `"chi"`, `"jpn"`).
///   `nil` when the USLT frame declares no language (i.e. the raw value is empty
///   or the sentinel `"und"`).
/// - `text`: raw lyrics text as stored in the frame, before any timestamp stripping.
///   Callers (e.g. `LyricsService`) are responsible for stripping LRC-style
///   timestamps when the source is a sidecar `.lrc` file.
public struct LyricsLanguageVariant: Codable, Equatable, Sendable {

    /// ISO 639-2 language code, or `nil` if undeclared.
    public let languageCode: String?

    /// Raw lyrics text (not yet stripped of timestamps or metadata tags).
    public let text: String

    public init(languageCode: String?, text: String) {
        self.languageCode = languageCode
        self.text = text
    }
}