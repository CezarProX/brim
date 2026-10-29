import Foundation

/// One assistant message's billed tokens, read from a Claude Code transcript.
struct UsageSample: Equatable {
  let date: Date
  let tokens: Int
  /// `message.id:requestId`; Claude Code writes a message once per content block, so duplicates must be dropped.
  let key: String
}

/// A plan-usage reading for one agent: how much of a rolling window is spent.
struct UsageReading: Equatable {
  let fraction: Double
  let resetsAt: Date?
  /// Tokens spent and the limit, when the figure is computed locally rather than reported by the agent.
  var used: Int?
  var limit: Int?

  var percent: Int { Int((fraction * 100).rounded()) }
}

enum AgentUsageMath {
  /// Claude's plan windows are 5 hours.
  static let windowLength: TimeInterval = 5 * 3600

  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  /// Billed tokens in one transcript line: input + output + cache writes. Cache reads are excluded because they
  /// are re-reads of context, not new spend, and would swamp the figure.
  static func sample(line: Data) -> UsageSample? {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      object["type"] as? String == "assistant",
      let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
      let stamp = object["timestamp"] as? String, let date = iso.date(from: stamp)
    else { return nil }
    let tokens = (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
      + (usage["cache_creation_input_tokens"] as? Int ?? 0)
    guard tokens > 0 else { return nil }
    let key = "\(message["id"] as? String ?? stamp):\(object["requestId"] as? String ?? "")"
    return UsageSample(date: date, tokens: tokens, key: key)
  }

  /// Tokens used in the window ending at `now`, with duplicates removed.
  static func windowTokens(_ samples: [UsageSample], now: Date, window: TimeInterval = windowLength) -> Int {
    var seen = Set<String>()
    var total = 0
    for sample in samples where now.timeIntervalSince(sample.date) <= window && sample.date <= now {
      if seen.insert(sample.key).inserted { total += sample.tokens }
    }
    return total
  }

  /// The window frees up when its oldest message ages out.
  static func resetDate(_ samples: [UsageSample], now: Date, window: TimeInterval = windowLength) -> Date? {
    samples.filter { now.timeIntervalSince($0.date) <= window }.map(\.date).min().map { $0.addingTimeInterval(window) }
  }

  static func reading(_ samples: [UsageSample], limit: Int, now: Date) -> UsageReading? {
    guard limit > 0 else { return nil }
    let used = windowTokens(samples, now: now)
    guard used > 0 else { return nil }
    return UsageReading(
      fraction: min(1, Double(used) / Double(limit)), resetsAt: resetDate(samples, now: now), used: used, limit: limit)
  }

  /// Codex stamps `rate_limits.primary.used_percent` (and `resets_at`) on its `token_count` events.
  static func codexReading(lines: [Data]) -> UsageReading? {
    var latest: UsageReading?
    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
        let limits = payload["rate_limits"] as? [String: Any], let primary = limits["primary"] as? [String: Any],
        let percent = (primary["used_percent"] as? NSNumber)?.doubleValue
      else { continue }
      let reset = (primary["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
      latest = UsageReading(fraction: min(1, max(0, percent / 100)), resetsAt: reset)
    }
    return latest
  }
}

/// Which usage alert, if any, a new reading should raise. Each level fires once per window.
enum UsageAlertPolicy {
  static let levels: [Double] = [0.80, 0.95]

  /// Returns the highest newly crossed level and the levels now considered alerted.
  static func evaluate(fraction: Double, alerted: Set<Double>) -> (fire: Double?, alerted: Set<Double>) {
    guard fraction >= levels[0] else { return (nil, []) }  // window rolled over: re-arm
    let crossed = levels.filter { fraction >= $0 }
    let fresh = crossed.filter { !alerted.contains($0) }
    return (fresh.max(), alerted.union(crossed))
  }
}
