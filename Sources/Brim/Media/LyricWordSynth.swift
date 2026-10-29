import Foundation

/// Word timing for line-synced lyrics. LRCLIB rarely ships enhanced (`<mm:ss.xx>`) tags, so a
/// line without them gets word start times interpolated across the time it is sung, weighted by
/// word length (longer words take longer). It is an estimate, not the singer's real phrasing.
enum LyricWordSynth {
  /// Longest a single line is assumed to be sung, however far apart the stamps are.
  static let maxSungSeconds: TimeInterval = 8
  /// The sung span ends this fraction before the next line, so the sweep finishes with a breath.
  static let breathFraction = 0.08
  static let fallbackLineSeconds: TimeInterval = 4

  /// Longest the last word of a line is assumed to be held past the sung pace.
  static let maxHoldSeconds: TimeInterval = 3.5
  /// A gap up to this many times the paced length is treated as fully sung.
  static let fillsGapRatio = 1.6

  /// When the words start (`words`) and when the line's sweep ends (`end`), both from the line
  /// stamp. A line that roughly fills its gap is spread across all of it; with room to spare the
  /// words keep a sung pace and the last one is held, because singers stretch the end of a phrase,
  /// capped so a short phrase before a long instrumental does not crawl.
  static func sungSpan(characters: Int, gap: TimeInterval?) -> (words: TimeInterval, end: TimeInterval) {
    let paced = max(1.0, Double(characters) * 0.09 + 0.6)
    let room = max(0.4, (gap.map { $0.isFinite && $0 > 0 ? $0 : fallbackLineSeconds } ?? fallbackLineSeconds) * (1 - breathFraction))
    if room <= paced * fillsGapRatio { return (min(maxSungSeconds, room), min(maxSungSeconds, room)) }
    let words = min(maxSungSeconds, paced * 1.25)
    return (words, min(room, words + maxHoldSeconds))
  }

  /// Relative effort for a word: its letters, plus a pause when it ends a clause.
  static func weight(of word: Substring) -> Double {
    let trimmed = word.trimmingCharacters(in: .whitespaces)
    let letters = trimmed.filter { $0.isLetter || $0.isNumber }.count
    let pause: Double = (trimmed.last.map { ",.;:!?…".contains($0) } ?? false) ? 2 : 0
    return Double(max(1, letters)) + pause
  }

  /// Synthesized words for `line`. Tags already in the file always win.
  /// `nextLineTime` is the stamp of the following line; nil for the last one.
  static func words(for line: LyricLine, nextLineTime: TimeInterval?) -> [LyricWord] {
    guard line.words.isEmpty else { return line.words }
    let tokens = line.text.split(separator: " ", omittingEmptySubsequences: true)
    guard !tokens.isEmpty else { return [] }
    let gap = nextLineTime.map { $0 - line.time }
    let span = sungSpan(characters: line.text.count, gap: gap).words
    let weights = tokens.map(weight(of:))
    let total = weights.reduce(0, +)
    var elapsed = 0.0
    var result: [LyricWord] = []
    for (index, token) in tokens.enumerated() {
      let suffix = index == tokens.count - 1 ? "" : " "
      result.append(LyricWord(time: line.time + span * elapsed / total, text: String(token) + suffix))
      elapsed += weights[index]
    }
    return result
  }

  /// Index of the word being sung at `time`; nil before the first word.
  static func activeIndex(in words: [LyricWord], at time: TimeInterval) -> Int? {
    guard time.isFinite, let first = words.first, time >= first.time else { return nil }
    return words.lastIndex { $0.time <= time }
  }

  /// How lit each word is at `time`, 0...1: a word fills over the time until the next one starts,
  /// the last one until `lineEnd`. This is what makes the sweep glide instead of stepping.
  static func fills(of words: [LyricWord], lineEnd: TimeInterval, at time: TimeInterval) -> [Double] {
    guard time.isFinite else { return words.map { _ in 0 } }
    return words.indices.map { index in
      let start = words[index].time
      let end = index + 1 < words.count ? words[index + 1].time : lineEnd
      let span = max(0.05, end - start)
      return min(1, max(0, (time - start) / span))
    }
  }

  /// When the last word of a file-tagged line is assumed to finish.
  static let taggedTailSeconds: TimeInterval = 0.8
}

extension TimedLyrics {
  /// Words of line `index` for the karaoke sweep: file tags, or interpolated for plain LRC.
  func sweepWords(at index: Int) -> [LyricWord] {
    guard lines.indices.contains(index) else { return [] }
    let next = index + 1 < lines.count ? lines[index + 1].time : nil
    return LyricWordSynth.words(for: lines[index], nextLineTime: next)
  }

  /// When the sweep of line `index` is complete; for a blank (instrumental) line, the next stamp.
  /// 0 for an index outside the lyrics.
  func sweepEnd(at index: Int) -> TimeInterval {
    guard lines.indices.contains(index) else { return 0 }
    let line = lines[index]
    let next = index + 1 < lines.count ? lines[index + 1].time : nil
    if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
      return next ?? line.time + LyricWordSynth.fallbackLineSeconds
    }
    if let end = line.end { return end }
    if let last = line.words.last {
      return min(next ?? .infinity, last.time + LyricWordSynth.taggedTailSeconds)
    }
    return line.time + LyricWordSynth.sungSpan(characters: line.text.count, gap: next.map { $0 - line.time }).end
  }
}
