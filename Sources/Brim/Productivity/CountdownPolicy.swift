import Foundation

/// A calendar event the user pinned with "Count down to this".
struct PinnedCountdown: Codable, Equatable {
  let eventID: String
  let title: String
  let start: Date
  let end: Date
}

/// How a countdown reads and when it is shown in the compact island.
enum CountdownPolicy {
  /// The ring fills over the last ten minutes before the event, like the meeting activity.
  static let ringWindow: TimeInterval = 600
  /// A pinned event stays visible this long after it starts, then drops off by itself.
  static let lingerAfterStart: TimeInterval = 60

  /// "1d 23h", "2h 05m", "in 5 min" style compact text, "4:19" in the last five minutes.
  static func label(until start: Date, now: Date) -> String {
    let seconds = Int(start.timeIntervalSince(now).rounded(.up))
    guard seconds > 0 else { return "Now" }
    if seconds >= 86_400 {
      return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h"
    }
    if seconds >= 3600 {
      return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }
    if seconds > 300 { return "\(Int((Double(seconds) / 60).rounded(.up))) min" }
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }

  /// The sentence form used in the details card: "in 5 min".
  static func phrase(until start: Date, now: Date) -> String {
    let text = label(until: start, now: now)
    return text == "Now" ? "Now" : "in " + text
  }

  /// Ring progress: 0 until the window opens, then 0...1 up to the start; 1 while the event runs.
  static func ringProgress(start: Date, end: Date, now: Date) -> Double {
    if now >= start {
      return 1 - min(1, max(0, now.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
    }
    let left = start.timeIntervalSince(now)
    return min(1, max(0, 1 - left / ringWindow))
  }

  /// Whether a pinned countdown should still occupy the compact island.
  static func isVisible(_ pin: PinnedCountdown, now: Date) -> Bool {
    now < pin.start.addingTimeInterval(lingerAfterStart)
  }

  /// Automatic meeting live activity: within the lead window until the event ends.
  static func isMeetingLive(start: Date, end: Date, now: Date, lead: TimeInterval = 600) -> Bool {
    start.timeIntervalSince(now) <= lead && end > now
  }
}
