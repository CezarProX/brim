import SwiftUI

@MainActor
final class IslandFlashCenter: ObservableObject {
  static let shared = IslandFlashCenter()
  @Published private(set) var current: IslandFlash?
  private var queue = HUDQueue()
  private var expiry: Timer?
  private var held = false

  /// Shows a flash. See `HUDQueue` for what replaces what; plain flashes behave as before
  /// (newest wins) unless a volume/brightness/keyboard HUD is on screen, which they wait for.
  func show(
    _ title: String, symbol: String, tint: Color = .white, value: Double? = nil,
    duration: TimeInterval = 2.2, kind: HUDKind = .general, detail: String? = nil,
    elapsedSince: Date? = nil, action: HUDAction? = nil, secondaryAction: HUDAction? = nil, airPods: AirPodsBatteries? = nil,
    shortTitle: String? = nil, autoOpenCard: TimeInterval? = nil, hero: Bool = false, now: Date = .now
  ) {
    let flash = IslandFlash(
      title: String(title.prefix(40)), symbol: symbol, tint: tint,
      value: value.map { min(1, max(0, $0)) }, until: now.addingTimeInterval(duration),
      kind: kind, duration: duration, detail: detail.map { String($0.prefix(60)) },
      elapsedSince: elapsedSince, action: action, secondaryAction: secondaryAction, airPods: airPods,
      shortTitle: shortTitle.map { String($0.prefix(20)) }, autoOpenCard: autoOpenCard, hero: hero)
    queue.offer(flash, now: now)
    sync(now: now)
  }

  func isVisible(now: Date = .now) -> Bool { current.map { $0.until > now } ?? false }

  /// While the pointer rests on a HUD card its flash stays up (Eject must stay reachable);
  /// on release it lingers a moment so it does not vanish under the pointer.
  func setHeld(_ value: Bool, now: Date = .now) {
    guard held != value else { return }
    held = value
    if !value { queue.ensureRemaining(0.9, now: now) }
    sync(now: now)
  }

  func dismiss() {
    queue.dismiss()
    sync(now: .now)
  }

  private func tick() {
    queue.advance(now: .now)
    sync(now: .now)
  }

  private func sync(now: Date) {
    if queue.current != current { current = queue.current }
    expiry?.invalidate()
    guard !held, let until = queue.current?.until else { return }
    expiry = Timer.scheduledTimer(withTimeInterval: max(0.05, until.timeIntervalSince(now)), repeats: false) {
      [weak self] _ in Task { @MainActor in self?.tick() }
    }
  }
}

/// Trailing compact content for a flash: a level bar and percent when there is a value, else its
/// (short) title. White text; the bar carries the tint (see `CompactLayout` for the colour rule).
/// Its width is exactly `CompactLayout.readoutWidth`, which the island's shape is sized from.
struct IslandFlashReadout: View {
  let flash: IslandFlash
  /// The pill gives the level bar more room than a notch wing.
  var floating = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if let value = flash.value {
        HStack(spacing: CompactLayout.barSpacing) {
          HUDLevelBar(
            value: value, tint: flash.tint,
            width: floating ? CompactLayout.pillBarWidth : CompactLayout.notchBarWidth, height: floating ? 6 : 5)
          Text("\(HUDLevelMath.percent(value))")
            .font(CompactLayout.labelFont).monospacedDigit()
            .foregroundStyle(IslandInk.primary)
            .contentTransition(.numericText())
            .frame(width: CompactLayout.percentWidth, alignment: .trailing)
        }
      } else {
        Text(flash.compactText).font(CompactLayout.labelFont).foregroundStyle(IslandInk.primary)
          .lineLimit(1).truncationMode(.tail).minimumScaleFactor(CompactLayout.labelMinimumScale)
      }
    }
    .frame(width: CompactLayout.readoutWidth(flash, floating: floating))
    .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0), value: flash.value)
  }
}
