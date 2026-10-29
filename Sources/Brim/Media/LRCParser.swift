import Foundation

struct LyricWord: Equatable, Sendable {
  let time: TimeInterval
  let text: String
}

struct LyricLine: Equatable, Sendable, Identifiable {
  let time: TimeInterval
  let text: String
  /// Word-by-word timing from enhanced LRC; empty for plain line-synced lyrics.
  let words: [LyricWord]
  /// When the line stops being sung, from a trailing word stamp; nil for plain LRC.
  let end: TimeInterval?
  var id: String { "\(time)|\(text)" }

  init(time: TimeInterval, text: String, words: [LyricWord], end: TimeInterval? = nil) {
    self.time = time
    self.text = text
    self.words = words
    self.end = end
  }

  /// Index of the word being sung at `time`, nil before the first word or without word timing.
  func activeWord(at time: TimeInterval) -> Int? {
    guard time.isFinite, let first = words.first, time >= first.time else { return nil }
    return words.lastIndex { $0.time <= time }
  }
}

struct TimedLyrics: Equatable, Sendable {
  let lines: [LyricLine]
  var isSynced: Bool { !lines.isEmpty }
  var hasWordTiming: Bool { lines.contains { !$0.words.isEmpty } }

  /// The line being sung at `time`: the last whose start is not after it. `lookahead`
  /// switches to the next line a little early so highlight changes feel on-beat.
  func index(at time: TimeInterval, lookahead: TimeInterval = 0) -> Int? {
    guard time.isFinite, !lines.isEmpty else { return nil }
    let target = time + max(0, lookahead)
    var low = 0, high = lines.count
    while low < high {
      let mid = (low + high) / 2
      if lines[mid].time <= target { low = mid + 1 } else { high = mid }
    }
    return low == 0 ? nil : low - 1
  }

  /// Previous, current and next lines (current only before the first line starts: the first).
  func window(at time: TimeInterval) -> [LyricLine] {
    guard !lines.isEmpty else { return [] }
    guard let current = index(at: time) else { return [lines[0]] }
    return Array(lines[max(0, current - 1)...min(lines.count - 1, current + 1)])
  }
}

enum LRCParser {
  static let maxLines = 5_000

  static func parse(_ source: String) -> TimedLyrics {
    var offset: TimeInterval = 0
    var lines: [LyricLine] = []
    let text = source.replacingOccurrences(of: "\u{FEFF}", with: "")
    for raw in text.split(whereSeparator: \.isNewline) {
      var rest = Substring(raw)
      var stamps: [TimeInterval] = []
      while rest.first == "[", let close = rest.firstIndex(of: "]") {
        let tag = rest[rest.index(after: rest.startIndex)..<close]
        rest = rest[rest.index(after: close)...]
        if let time = timestamp(tag) { stamps.append(time) }
        else if tag.lowercased().hasPrefix("offset:"),
          let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
          offset = ms / 1000
        }
      }
      guard !stamps.isEmpty else { continue }
      let (words, end) = enhancedWords(String(rest))
      let plain = words.isEmpty ? String(rest).trimmingCharacters(in: .whitespaces)
        : words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
      for stamp in stamps {
        let shift = { (value: TimeInterval) in max(0, value - offset) }
        lines.append(LyricLine(time: shift(stamp), text: plain,
                               words: words.map { LyricWord(time: shift($0.time), text: $0.text) },
                               end: end.map(shift)))
        if lines.count >= maxLines { break }
      }
      if lines.count >= maxLines { break }
    }
    // Offsets apply to every line, wherever the tag sat in the file.
    let ordered = lines.enumerated().sorted {
      $0.element.time != $1.element.time ? $0.element.time < $1.element.time : $0.offset < $1.offset
    }.map(\.element)
    return TimedLyrics(lines: ordered)
  }

  /// `mm:ss`, `mm:ss.xx`, `mm:ss.xxx` or `mm:ss:xx`.
  static func timestamp(_ tag: Substring) -> TimeInterval? {
    let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
    let secondsText = parts[1]
    var fraction = 0.0
    var secondsPart = secondsText
    if parts.count == 3 {
      guard let f = Double("0." + parts[2]) else { return nil }
      fraction = f
    } else if let dot = secondsText.firstIndex(of: ".") {
      guard let f = Double("0." + secondsText[secondsText.index(after: dot)...]) else { return nil }
      fraction = f
      secondsPart = secondsText[..<dot]
    }
    guard let seconds = Int(secondsPart), seconds >= 0, seconds < 100 else { return nil }
    return Double(minutes * 60 + seconds) + fraction
  }

  /// `<mm:ss.xx>word ` runs; a line without inline stamps yields no words. A stamp with nothing
  /// after it closes the last word and is returned as the line's end.
  private static func enhancedWords(_ text: String) -> (words: [LyricWord], end: TimeInterval?) {
    guard text.contains("<") else { return ([], nil) }
    var words: [LyricWord] = []
    var currentTime: TimeInterval?
    var buffer = ""
    var index = text.startIndex
    func flush() {
      if let time = currentTime, !buffer.isEmpty { words.append(LyricWord(time: time, text: buffer)) }
      buffer = ""
    }
    while index < text.endIndex {
      if text[index] == "<", let close = text[index...].firstIndex(of: ">"),
        let time = timestamp(text[text.index(after: index)..<close]) {
        flush()
        currentTime = time
        index = text.index(after: close)
      } else {
        buffer.append(text[index])
        index = text.index(after: index)
      }
    }
    if let time = currentTime, buffer.trimmingCharacters(in: .whitespaces).isEmpty, !words.isEmpty {
      return (words, time)
    }
    flush()
    return (words, nil)
  }
}
