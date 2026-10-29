import Foundation

/// The auto-close countdown of one thumbnail. Anything that holds the card (hover, pin, a drag, a
/// running action, a new capture in progress) pauses it; letting go resumes with at least
/// `resumeGrace` left, so a card never vanishes the instant the pointer leaves it.
struct ThumbnailDismissClock: Equatable {
  enum Hold: Hashable { case hover, pin, drag, busy, suspended }

  static let resumeGrace: TimeInterval = 2

  /// Seconds before closing; 0 or less never closes by itself.
  let delay: TimeInterval
  private(set) var holds: Set<Hold> = []
  /// When the card should close; nil while held, or when it never closes by itself.
  private(set) var deadline: Date?
  private var remaining: TimeInterval

  init(delay: TimeInterval, start now: Date) {
    self.delay = delay
    remaining = delay
    deadline = delay > 0 ? now.addingTimeInterval(delay) : nil
  }

  var isPaused: Bool { !holds.isEmpty }

  mutating func hold(_ hold: Hold, at now: Date) {
    if holds.isEmpty, let deadline { remaining = max(0, deadline.timeIntervalSince(now)) }
    holds.insert(hold)
    deadline = nil
  }

  mutating func release(_ hold: Hold, at now: Date) {
    guard holds.remove(hold) != nil, holds.isEmpty, delay > 0 else { return }
    remaining = max(remaining, min(delay, Self.resumeGrace))
    deadline = now.addingTimeInterval(remaining)
  }

  mutating func set(_ hold: Hold, _ held: Bool, at now: Date) {
    if held { self.hold(hold, at: now) } else { release(hold, at: now) }
  }

  /// Starts the full delay again (a fresh image for the same capture, or an action just finished).
  mutating func restart(at now: Date) {
    remaining = delay
    deadline = holds.isEmpty && delay > 0 ? now.addingTimeInterval(delay) : nil
  }

  func isExpired(at now: Date) -> Bool {
    deadline.map { now >= $0 } ?? false
  }
}
