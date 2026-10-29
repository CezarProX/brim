import Foundation
import SwiftUI

/// Decides when a HUD shows its card rather than its strip. Hover always shows the card. A flash
/// that asks for it (the AirPods connect card) also opens its card by itself for a few seconds the
/// moment it becomes visible, like an iPhone connect sheet; resting the pointer on it keeps it open,
/// and leaving restarts the countdown. Pure state, driven by the shell's tick, so it can be tested.
struct HUDAutoCard: Equatable {
  private(set) var flashID: UUID?
  /// When the self-opened card collapses back to the strip; nil once it has (or never opened).
  private(set) var closesAt: TimeInterval?
  private var openFor: TimeInterval = 0
  private var wasHovered = false

  /// Whether the card should show now.
  mutating func update(flash: IslandFlash?, hovered: Bool, now: TimeInterval) -> Bool {
    if flash?.id != flashID {
      flashID = flash?.id
      openFor = flash?.autoOpenCard ?? 0
      closesAt = openFor > 0 ? now + openFor : nil
      wasHovered = false
    }
    guard flash != nil else { return false }
    defer { wasHovered = hovered }
    if hovered { return true }
    if wasHovered, closesAt != nil { closesAt = now + openFor }
    guard let closesAt else { return false }
    if now < closesAt { return true }
    self.closesAt = nil
    return false
  }

  var isAutoOpen: Bool { closesAt != nil }
}

/// The AirPods connect card: the one place it is presented, so the Bluetooth monitor and tests share it.
@MainActor
enum AirPodsConnectCard {
  /// Seconds the card opens by itself before folding back into the strip.
  static let autoOpenDuration: TimeInterval = 3
  /// The whole flash: the open card plus a moment as a strip.
  static let duration: TimeInterval = 4.5

  static func present(_ pods: AirPodsBatteries, name: String, center: IslandFlashCenter? = nil) {
    (center ?? .shared).show(
      name, symbol: pods.symbol, tint: .white, duration: duration, kind: .bluetooth,
      detail: "Connected", airPods: pods, shortTitle: "Connected", autoOpenCard: autoOpenDuration)
  }
}
