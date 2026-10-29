import Foundation

/// How often and how recently a result was chosen. Persisted per result id.
struct ThunderFrecency: Codable, Equatable, Sendable {
  var count: Int
  var lastUsed: Date

  /// Boost added to a matched result. Grows with log(count) and halves every two weeks.
  func bonus(now: Date) -> Double {
    let days = max(0, now.timeIntervalSince(lastUsed) / 86_400)
    return min(160, 45 * log2(1 + Double(count))) * pow(0.5, days / 14)
  }

  static func recording(_ id: String, in table: [String: ThunderFrecency], now: Date) -> [String: ThunderFrecency] {
    var updated = table
    let previous = table[id]
    updated[id] = ThunderFrecency(count: (previous?.count ?? 0) + 1, lastUsed: now)
    // Keep the table bounded: drop the stalest entries beyond 400.
    guard updated.count > 400 else { return updated }
    let keep = updated.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(400)
    return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
  }
}

/// Fuzzy matching: exact > prefix > word prefix > substring > in-order subsequence.
enum ThunderFuzzy {
  static func score(query: String, in candidate: String) -> Double? {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    let text = candidate.lowercased()
    guard !q.isEmpty, !text.isEmpty else { return nil }
    if text == q { return 1000 }
    if text.hasPrefix(q) { return 800 - Double(text.count - q.count) * 0.5 }
    if let range = text.range(of: q) {
      let start = text.distance(from: text.startIndex, to: range.lowerBound)
      let before = text[text.index(before: range.lowerBound)]
      if !before.isLetter && !before.isNumber { return 620 - Double(start) * 0.5 }
      return 420 - Double(start) * 0.5
    }
    return subsequence(Array(q), Array(text))
  }

  private static func subsequence(_ q: [Character], _ text: [Character]) -> Double? {
    guard q.count >= 2, q.count <= text.count else { return nil }
    var index = 0
    var score = 100.0
    var streak = 0
    var previousMatch = -2
    for (position, character) in text.enumerated() where index < q.count && character == q[index] {
      let boundary = position == 0 || !(text[position - 1].isLetter || text[position - 1].isNumber)
      streak = position == previousMatch + 1 ? streak + 1 : 0
      score += Double(streak) * 12 + (boundary ? 18 : 0) - Double(position - max(previousMatch, -1) - 1) * 1.5
      previousMatch = position
      index += 1
    }
    return index == q.count ? max(20, score - Double(text.count) * 0.4) : nil
  }
}

struct ThunderCandidate: Equatable, Sendable {
  let id: String
  let title: String
  /// Extra searchable text (bundle id, path, tags); matches here count a little less.
  var keywords: String = ""
  /// Per-kind nudge so, at equal text match, apps come before files before clipboard.
  var kindBoost: Double = 0
}

enum ThunderRanking {
  /// Ranks `candidates` for `query`. An empty query returns the most-used ones.
  static func rank(
    _ candidates: [ThunderCandidate], query: String, frecency: [String: ThunderFrecency],
    now: Date = .now, limit: Int = 50
  ) -> [ThunderCandidate] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let scored: [(ThunderCandidate, Double)] = candidates.compactMap { candidate in
      let used = frecency[candidate.id]?.bonus(now: now) ?? 0
      guard !trimmed.isEmpty else { return used > 0 ? (candidate, used) : nil }
      let titleScore = ThunderFuzzy.score(query: trimmed, in: candidate.title)
      let keywordScore = candidate.keywords.isEmpty ? nil : ThunderFuzzy.score(query: trimmed, in: candidate.keywords).map { $0 * 0.55 }
      guard let base = [titleScore, keywordScore].compactMap({ $0 }).max() else { return nil }
      return (candidate, base + used + candidate.kindBoost)
    }
    return scored
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending }
      .prefix(limit).map(\.0)
  }
}
