import Combine
import Foundation

/// A small readout that can sit beside the closed island.
enum IslandGlance: String, CaseIterable, Identifiable, Sendable {
  case none, clock, battery, timer, weather, cpu, event
  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: "Nothing"
    case .clock: "Clock"
    case .battery: "Battery"
    case .timer: "Timer"
    case .weather: "Weather"
    case .cpu: "CPU load"
    case .event: "Next event"
    }
  }

  var symbol: String {
    switch self {
    case .none: "circle.dashed"
    case .clock: "clock"
    case .battery: "battery.75percent"
    case .timer: "timer"
    case .weather: "cloud.sun"
    case .cpu: "cpu"
    case .event: "calendar"
    }
  }
}

enum GlanceSlot: String, Sendable { case left, right }

/// Text for each glance, kept free of views so it can be tested.
enum GlanceFormat {
  static func clock(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
    let style = Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute()
    // "9:41 AM" is too wide for a wing; keep the digits and drop the day period.
    return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
      .split(separator: " ").first.map(String.init) ?? ""
  }

  static func battery(percent: Int) -> String { "\(min(100, max(0, percent)))%" }

  static func batterySymbol(percent: Int, charging: Bool) -> String {
    if charging { return "battery.100percent.bolt" }
    switch percent {
    case ..<10: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
  }

  /// 59:59 under an hour, 1:05:00 above.
  static func timer(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
  }

  static func cpu(_ usage: Double) -> String { "\(Int((min(1, max(0, usage)) * 100).rounded()))%" }

  /// "Standup 3:30": the title cut to fit a wing, then the start time. "Now" once it has begun.
  static func event(title: String, startsAt: Date, now: Date = .now, locale: Locale = .current,
                    timeZone: TimeZone = .current, maxTitle: Int = 11) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let short = trimmed.count > maxTitle ? String(trimmed.prefix(maxTitle - 1)) + "…" : trimmed
    let when = startsAt <= now ? "Now" : clock(startsAt, locale: locale, timeZone: timeZone)
    return short.isEmpty ? when : "\(short) \(when)"
  }
}

/// Which glance is on the left and right of the closed island, and the live values they show.
@MainActor
final class IslandGlanceModel: ObservableObject {
  static let shared = IslandGlanceModel()
  /// Width the shell should reserve for a glance in a wing.
  static let glanceWidth: CGFloat = 64

  /// Wider readouts (the next event) than the standard glance.
  static let eventGlanceWidth: CGFloat = 132
  /// Gap between two glances on the same side.
  static let glanceSpacing: CGFloat = 8

  @Published private(set) var left: IslandGlance
  @Published private(set) var right: IslandGlance
  @Published private(set) var leftSecond: IslandGlance
  @Published private(set) var rightSecond: IslandGlance
  @Published private(set) var batteryPercent: Int?
  @Published private(set) var batteryCharging = false
  private let settings: AppSettings
  private var cancellables: Set<AnyCancellable> = []
  private var batteryTimer: Timer?
  private var attachedToStats = false

  /// `battery` seeds renders and tests; the app reads the real battery once a glance needs it.
  init(settings: AppSettings = .shared, battery: (percent: Int, charging: Bool)? = nil) {
    self.settings = settings
    batteryPercent = battery?.percent
    batteryCharging = battery?.charging ?? false
    left = IslandGlance(rawValue: settings.glanceLeft) ?? .none
    right = IslandGlance(rawValue: settings.glanceRight) ?? .none
    leftSecond = IslandGlance(rawValue: settings.glanceLeftSecond) ?? .none
    rightSecond = IslandGlance(rawValue: settings.glanceRightSecond) ?? .none
  }

  /// Call at launch. Re-publishes timer and weather changes so a shell observing only this model updates.
  func start() {
    guard cancellables.isEmpty else { return }
    FocusTimerModel.shared.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    WeatherStore.shared.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    CalendarActivityModel.shared.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    SystemStatsModel.shared.$cpu.sink { [weak self] _ in
      if self?.uses(.cpu) == true { self?.objectWillChange.send() }
    }.store(in: &cancellables)
    updateSources()
  }

  /// The first glance of a side, the one next to the camera.
  func glance(for slot: GlanceSlot) -> IslandGlance { slot == .left ? left : right }

  /// Both configured glances of a side, nearest the camera first (`none` included).
  func configured(for slot: GlanceSlot) -> [IslandGlance] {
    slot == .left ? [left, leftSecond] : [right, rightSecond]
  }

  func set(_ glance: IslandGlance, for slot: GlanceSlot, second: Bool = false) {
    switch (slot, second) {
    case (.left, false): left = glance; settings.glanceLeft = glance.rawValue
    case (.left, true): leftSecond = glance; settings.glanceLeftSecond = glance.rawValue
    case (.right, false): right = glance; settings.glanceRight = glance.rawValue
    case (.right, true): rightSecond = glance; settings.glanceRightSecond = glance.rawValue
    }
    updateSources()
  }

  /// The glances with something to say on a side, nearest the camera first (a duplicate shows once).
  func visible(for slot: GlanceSlot) -> [IslandGlance] {
    var seen: Set<IslandGlance> = []
    return configured(for: slot).filter { hasContent($0) && seen.insert($0).inserted }
  }

  /// False while the glance has nothing to say (an idle timer, weather that is off), so the wing stays empty.
  func hasContent(_ slot: GlanceSlot) -> Bool { !visible(for: slot).isEmpty }

  func hasContent(_ glance: IslandGlance) -> Bool {
    switch glance {
    case .none: false
    case .clock, .cpu: true
    case .battery: batteryPercent != nil
    case .timer: FocusTimerModel.shared.isActive
    case .weather: WeatherStore.shared.snapshot != nil && settings.weatherEnabled
    case .event: CalendarActivityModel.shared.meeting != nil
    }
  }

  static func width(of glance: IslandGlance) -> CGFloat { glance == .event ? eventGlanceWidth : glanceWidth }

  /// Extra width the shell should add to a wing for its glances.
  func reservedWidth(_ slot: GlanceSlot) -> CGFloat {
    let shown = visible(for: slot)
    guard !shown.isEmpty else { return 0 }
    return shown.reduce(0) { $0 + Self.width(of: $1) } + CGFloat(shown.count - 1) * Self.glanceSpacing
  }

  private func uses(_ glance: IslandGlance) -> Bool {
    [left, right, leftSecond, rightSecond].contains(glance)
  }

  private func updateSources() {
    if uses(.battery) {
      readBattery()
      if batteryTimer == nil {
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
          Task { @MainActor in self?.readBattery() }
        }
      }
    } else {
      batteryTimer?.invalidate()
      batteryTimer = nil
    }
    if uses(.cpu), !attachedToStats {
      attachedToStats = true
      SystemStatsModel.shared.attach()
    } else if !uses(.cpu), attachedToStats {
      attachedToStats = false
      SystemStatsModel.shared.detach()
    }
  }

  private func readBattery() {
    let reading = SystemStatsReaders.battery()
    batteryPercent = reading?.percent
    batteryCharging = reading?.charging ?? false
  }
}
