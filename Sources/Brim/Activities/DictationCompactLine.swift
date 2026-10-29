// DictationCompactLine.swift
// Brim
//
// The live transcript line shown in the closed island while dictation is running: the last few
// words, newest at the right edge, so it reads like a caption.

import SwiftUI

enum DictationCompactLine {
  static let placeholder = "Listening"

  /// The trailing words of `transcript` that fit in `maxCharacters` (never cutting a word unless a
  /// single word is longer than the limit), prefixed with an ellipsis when earlier text was dropped.
  static func tail(_ transcript: String, maxCharacters: Int = 22) -> String {
    let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return placeholder }
    let limit = max(4, maxCharacters)
    var picked: [String] = []
    var length = 0
    for word in words.reversed() {
      let added = word.count + (picked.isEmpty ? 0 : 1)
      if length + added > limit {
        if picked.isEmpty { picked = [String(word.suffix(limit - 1))]; length = limit }
        break
      }
      picked.insert(word, at: 0)
      length += added
    }
    let dropped = picked.joined(separator: " ") != words.joined(separator: " ")
    return (dropped ? "…" : "") + picked.joined(separator: " ")
  }
}

/// Right wing of the closed island while dictating.
struct DictationCompactTrailing: View {
  @ObservedObject var model: DictationModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let width: CGFloat = 104

  var body: some View {
    let line = DictationCompactLine.tail(model.transcript)
    Text(line)
      .font(IslandFont.label.weight(.medium))
      .foregroundStyle(model.transcript.isEmpty ? IslandInk.tertiary : IslandInk.primary)
      .lineLimit(1).truncationMode(.head)
      .frame(width: Self.width, alignment: .trailing)
      .contentTransition(.opacity)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: line)
      .accessibilityLabel("Dictation: \(model.transcript.isEmpty ? "listening" : model.transcript)")
  }
}
