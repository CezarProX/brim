// TeleprompterMath.swift
// Brim
//
// Pure scroll math for the teleprompter, kept free of UI so it can be tested exactly.

import Foundation

enum TeleprompterMath {
  static let levels = 1...20
  static let maxScriptLength = 200_000

  static func clampLevel(_ level: Int) -> Int { min(levels.upperBound, max(levels.lowerBound, level)) }

  /// Scroll speed in points per second: level 1 is a slow 9 pt/s, level 20 a fast 66 pt/s.
  static func pointsPerSecond(level: Int) -> Double { 6 + Double(clampLevel(level)) * 3 }

  /// Words per minute the speed corresponds to at a font size (about 9 words per 24 pt line, line = 1.45 x font).
  static func approximateWordsPerMinute(level: Int, fontSize: Double, wordsPerLine: Double = 5) -> Int {
    let linesPerSecond = pointsPerSecond(level: level) / (fontSize * 1.45)
    return Int((linesPerSecond * wordsPerLine * 60).rounded())
  }

  struct Step: Equatable {
    var offset: Double
    var finished: Bool
  }

  /// The offset after `dt` seconds of scrolling. Scrolling ends once the last line has passed the reading line.
  static func advance(offset: Double, dt: Double, level: Int, contentHeight: Double) -> Step {
    guard dt > 0, contentHeight > 0 else { return Step(offset: max(0, offset), finished: false) }
    let next = max(0, offset) + pointsPerSecond(level: level) * min(dt, 0.25)  // a stalled frame never jumps
    if next >= contentHeight { return Step(offset: contentHeight, finished: true) }
    return Step(offset: next, finished: false)
  }

  /// 0...1 progress through the script.
  static func progress(offset: Double, contentHeight: Double) -> Double {
    guard contentHeight > 0 else { return 0 }
    return min(1, max(0, offset / contentHeight))
  }

  /// Whole seconds left at the current speed.
  static func secondsRemaining(offset: Double, level: Int, contentHeight: Double) -> Int {
    let left = max(0, contentHeight - offset)
    return Int((left / pointsPerSecond(level: level)).rounded(.up))
  }

  /// "3:05" style duration.
  static func clock(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
  }

  /// Script text split into paragraphs, with runs of blank lines collapsed.
  static func paragraphs(_ script: String) -> [String] {
    script.replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  static func wordCount(_ script: String) -> Int {
    script.split(whereSeparator: { $0.isWhitespace }).count
  }
}
