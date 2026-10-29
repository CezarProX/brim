import SwiftUI

/// Keep Awake, opened: one big switch like an Amphetamine session, how long is left, quick durations
/// (tapping one starts right away) and whether the screen may sleep.
struct KeepAwakeAppView: View {
  @ObservedObject var model: KeepAwakeModel
  /// Whether new sessions keep the screen on; shared with Settings > Droplets.
  @State private var keepsDisplayOn = AppSettings.shared.stayAwakeKeepDisplayOn
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Minutes for each chip; nil is "until you turn it off".
  static let durations: [Int?] = [15, 30, 60, 120, 240, nil]

  static func label(minutes: Int?) -> String {
    guard let minutes else { return L10n.tr("Until off") }
    if minutes < 60 { return L10n.tr("%lld min", minutes) }
    return L10n.tr("%lld h", minutes / 60)
  }

  /// Fraction of the session still to run, for the ring (1 = full, nil = open-ended).
  static func remainingFraction(until: Date?, startedAt: Date?, now: Date) -> Double? {
    guard let until, let startedAt else { return nil }
    let total = until.timeIntervalSince(startedAt)
    guard total > 0 else { return 0 }
    return min(1, max(0, until.timeIntervalSince(now) / total))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      hero
      chips
      displayRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isActive)
  }

  // MARK: Hero

  private var hero: some View {
    HStack(spacing: IslandSpace.l) {
      switchButton
      VStack(alignment: .leading, spacing: 2) {
        Text(model.isActive ? L10n.tr("Staying awake") : L10n.tr("Sleeps normally"))
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(model.isActive ? Color.yellow : IslandInk.secondary)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(headline(at: context.date))
            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(model.isActive ? IslandInk.primary : IslandInk.tertiary)
            .contentTransition(.numericText(countsDown: true))
            .minimumScaleFactor(0.7).lineLimit(1)
        }
        Text(caption).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private var switchButton: some View {
    Button {
      withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
        if model.isActive { model.stop() } else { model.start(minutes: nil, keepDisplayOn: keepsDisplayOn) }
      }
    } label: {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        ZStack {
          Circle().fill(model.isActive ? Color.yellow : IslandFill.raised)
          if let fraction = Self.remainingFraction(until: model.until, startedAt: model.startedAt, now: context.date) {
            IslandRing(progress: fraction, tint: .black.opacity(0.35), lineWidth: 4).padding(5)
          }
          Image(systemName: model.isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer.fill")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(model.isActive ? Color.black : IslandInk.primary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: model.isActive && !reduceMotion)
        }
        .frame(width: 84, height: 84)
      }
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.92))
    .help(model.isActive ? L10n.tr("Let the Mac sleep again") : L10n.tr("Keep the Mac awake until you turn it off"))
    .accessibilityLabel(model.isActive ? L10n.tr("Allow sleep") : L10n.tr("Keep awake"))
    .accessibilityValue(model.isActive ? L10n.tr("On") : L10n.tr("Off"))
  }

  private func headline(at now: Date) -> String {
    guard model.isActive else { return L10n.tr("Off") }
    guard let until = model.until else { return "∞" }
    return CompactTimerReadout.format(max(0, until.timeIntervalSince(now)))
  }

  private var caption: String {
    if let until = model.until {
      return L10n.tr("Your Mac stays awake until %@", until.formatted(date: .omitted, time: .shortened))
    }
    return model.isActive
      ? L10n.tr("Stays awake until you turn this off")
      : L10n.tr("Tap the cup, or pick a time below, to keep it awake")
  }

  // MARK: Durations

  private var chips: some View {
    HStack(spacing: 6) {
      ForEach(Self.durations, id: \.self) { minutes in
        let selected = model.isActive && model.sessionMinutes == minutes
        Button {
          withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
            model.start(minutes: minutes, keepDisplayOn: keepsDisplayOn)
          }
        } label: {
          Text(Self.label(minutes: minutes))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? Color.black : IslandInk.primary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(selected ? Color.yellow : IslandFill.raised, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.95))
        .accessibilityLabel(Self.label(minutes: minutes))
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  // MARK: Display

  private var displayRow: some View {
    HStack(spacing: IslandSpace.m) {
      Image(systemName: "display").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 1) {
        Text("Keep the screen on too").font(.system(size: 13, weight: .semibold))
        Text("Closing a MacBook's lid still puts it to sleep.")
          .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      Spacer(minLength: IslandSpace.s)
      Toggle("Keep the screen on too", isOn: $keepsDisplayOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        .tint(.yellow)
    }
    .padding(.horizontal, IslandSpace.m).frame(minHeight: 44)
    .islandAppCard()
    .onChange(of: keepsDisplayOn) { _, on in
      AppSettings.shared.stayAwakeKeepDisplayOn = on
      model.setKeepsDisplayOn(on)
    }
    .onChange(of: model.keepsDisplayOn) { _, on in if model.isActive { keepsDisplayOn = on } }
  }
}
