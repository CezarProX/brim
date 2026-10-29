import Foundation
import Intents
import SwiftUI

/// Focus on/off, as a flash and as a quiet "Focus · On" activity while it lasts.
///
/// macOS has no public push API for Focus, so the state is read, in order, from:
///  1. `INFocusStatusCenter`, once the user allowed it (needs `NSFocusStatusUsageDescription`),
///  2. the Focus assertion store (`FocusAssertions`, readable with Full Disk Access),
///  3. the distributed notifications Do Not Disturb has historically posted (a toggle guess).
/// The first two are re-read every few seconds and whenever a notification arrives.
@MainActor
final class FocusHUDMonitor {
  static let shared = FocusHUDMonitor()
  static let notificationNames = [
    "com.apple.donotdisturb.stateChanged", "com.apple.notificationcenterui.dndprefs_changed",
  ]
  static let pollInterval: TimeInterval = 5
  private var tokens: [NSObjectProtocol] = []
  private var timer: Timer?
  private var isOn: Bool?
  private var lastEvent = Date.distantPast

  func refresh() {
    let center = DistributedNotificationCenter.default()
    if AppSettings.shared.hudFocus {
      if tokens.isEmpty {
        tokens = Self.notificationNames.map { name in
          center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
            let flag = (note.userInfo?["state"] ?? note.userInfo?["enabled"]) as? NSNumber
            Task { @MainActor in self?.notified(explicit: flag?.boolValue) }
          }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
          Task { @MainActor in self?.evaluate(guess: nil) }
        }
        timer?.tolerance = 2
        evaluate(guess: nil)
      }
    } else {
      tokens.forEach(center.removeObserver)
      tokens = []
      timer?.invalidate()
      timer = nil
      isOn = nil
      SystemStatusIndicators.shared.setFocus(false)
    }
  }

  private func notified(explicit: Bool?) {
    // Both notification names often fire for one change.
    guard Date.now.timeIntervalSince(lastEvent) > 0.5 else { return }
    lastEvent = .now
    evaluate(guess: explicit ?? isOn.map { !$0 } ?? true)
  }

  private func evaluate(guess: Bool?) {
    let stored = FocusAssertions.read()
    let known = Self.intentFocus() ?? stored?.active
    apply(on: known ?? guess ?? isOn ?? false, name: stored?.name)
  }

  func apply(on: Bool, name: String?) {
    let previous = isOn
    isOn = on
    SystemStatusIndicators.shared.setFocus(on, name: name)
    guard let previous, previous != on else { return }
    IslandFlashCenter.shared.show(
      on ? (name.map { "\($0) On" } ?? "Focus On") : "Focus Off", symbol: on ? "moon.fill" : "moon",
      tint: on ? .indigo : .white, duration: 2.4, kind: .focus, shortTitle: on ? "Focus" : "Focus off")
  }

  /// `INFocusStatusCenter`'s answer when the app may ask; nil when it cannot or has not been allowed.
  private static func intentFocus() -> Bool? {
    guard Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") != nil else { return nil }
    let center = INFocusStatusCenter.default
    switch center.authorizationStatus {
    case .authorized: return center.focusStatus.isFocused
    case .notDetermined:
      center.requestAuthorization { _ in }
      return nil
    default: return nil
    }
  }
}
