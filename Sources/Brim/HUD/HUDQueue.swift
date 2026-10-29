import Foundation
import SwiftUI

/// What a HUD is about. Level HUDs (volume, brightness, keyboard backlight) are updated
/// continuously while a key is held, so nothing else may interrupt them mid-press.
enum HUDKind: Hashable {
  case volume, brightness, keyboard
  case wifi, offline, vpn, drive, bluetooth, focus, quitGuard
  case general

  var isLevel: Bool { self == .volume || self == .brightness || self == .keyboard }
}

/// A button shown on the HUD card (the notch strip itself is click-through), such as Eject.
struct HUDAction: Equatable, Identifiable {
  let id = UUID()
  let title: String
  let symbol: String
  let perform: @MainActor () -> Void

  static func == (lhs: HUDAction, rhs: HUDAction) -> Bool { lhs.id == rhs.id }
}

/// A short status that shows in the compact island for a moment, then disappears:
/// Caps Lock, charging, a finished timer, a volume change.
struct IslandFlash: Equatable, Identifiable {
  let id = UUID()
  let title: String
  let symbol: String
  let tint: Color
  /// Optional 0...1 level rendered as a bar, such as volume or battery.
  let value: Double?
  var until: Date
  var kind: HUDKind = .general
  var duration: TimeInterval = 2.2
  /// Secondary line for the expanded card, such as a network name or drive size.
  var detail: String? = nil
  /// When set, the card shows a live elapsed timer (VPN connected for 12:04).
  var elapsedSince: Date? = nil
  var action: HUDAction? = nil
  var secondaryAction: HUDAction? = nil
  /// AirPods connect card: per-bud and case levels with the model glyph.
  var airPods: AirPodsBatteries? = nil
  /// Short form for the narrow wing ("Quit Xcode?"); the card uses `title`.
  var shortTitle: String? = nil
  /// Seconds the card opens by itself when the flash appears (AirPods connect); nil = hover only.
  var autoOpenCard: TimeInterval? = nil
  /// The card leads with a large glowing glyph (Full Battery) instead of the usual one-line header.
  var hero = false

  /// The same flash, restarted at `now`: queued flashes get their full time once they show.
  func restarted(at now: Date) -> IslandFlash {
    var copy = self
    copy.until = now.addingTimeInterval(duration)
    return copy
  }
}

/// Pure queue policy behind `IslandFlashCenter`, kept free of timers so it can be tested.
///  - A level HUD replaces whatever is showing, and the newest level HUD replaces an older one.
///  - A flash of the same kind as the one showing replaces it in place.
///  - Any other flash arriving during a level HUD waits (one per kind, newest wins) and shows after.
///  - Two different non-level flashes: the newest wins, as before.
struct HUDQueue {
  private(set) var current: IslandFlash?
  private(set) var pending: [IslandFlash] = []
  static let pendingLimit = 4
  /// A bumped flash with at least this long left goes back in the queue instead of being lost.
  static let requeueThreshold: TimeInterval = 1

  /// Returns true when `flash` became the visible one.
  @discardableResult
  mutating func offer(_ flash: IslandFlash, now: Date) -> Bool {
    advance(now: now)
    guard let shown = current else {
      current = flash
      return true
    }
    if flash.kind.isLevel || shown.kind == flash.kind {
      if flash.kind.isLevel, !shown.kind.isLevel, shown.until.timeIntervalSince(now) > Self.requeueThreshold {
        pending.removeAll { $0.kind == shown.kind }
        pending.insert(shown, at: 0)
      }
      pending.removeAll { $0.kind == flash.kind }
      current = flash
      return true
    }
    if shown.kind.isLevel { return enqueue(flash) }
    current = flash
    return true
  }

  private mutating func enqueue(_ flash: IslandFlash) -> Bool {
    pending.removeAll { $0.kind == flash.kind }
    pending.append(flash)
    if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
    return false
  }

  /// Drops an expired current flash and promotes the next live pending one. Returns whether
  /// the visible flash changed.
  @discardableResult
  mutating func advance(now: Date) -> Bool {
    var changed = false
    if let shown = current, shown.until <= now {
      current = nil
      changed = true
    }
    if current == nil {
      if !pending.isEmpty {
        current = pending.removeFirst().restarted(at: now)
        changed = true
      }
    }
    return changed
  }

  mutating func dismiss() {
    current = nil
    pending.removeAll()
  }

  /// Keeps the visible flash up for at least `seconds` more, so a pointer leaving the card
  /// does not make it vanish the same instant.
  mutating func ensureRemaining(_ seconds: TimeInterval, now: Date) {
    guard var shown = current, shown.until < now.addingTimeInterval(seconds) else { return }
    shown.until = now.addingTimeInterval(seconds)
    current = shown
  }
}
