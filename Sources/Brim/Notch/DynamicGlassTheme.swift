import AppKit
import SwiftUI

/// The live surface settings the open island paints with. Settings writes through this, so a change
/// shows on the island at once (the glass level previews while you drag the slider).
@MainActor
final class IslandTheme: ObservableObject {
  static let shared = IslandTheme()

  @Published private(set) var surface: IslandSurfaceStyle
  @Published private(set) var glassLevel: Double
  @Published private(set) var tinted: Bool
  @Published private(set) var clarity: Double
  @Published private(set) var lightGlassInLightMode: Bool
  @Published private(set) var highlightHex: String
  @Published private(set) var windowTintHex: String
  @Published private(set) var progressiveBlur: Bool
  @Published private(set) var lowBatteryEnabled: Bool
  /// Lighter visuals are in force (battery under 20% or Low Power Mode).
  @Published private(set) var lowBatteryActive = false
  /// macOS is in Light appearance.
  @Published private(set) var systemIsLight = false
  private let settings: AppSettings
  private var monitors: [NSObjectProtocol] = []
  private var distributedMonitors: [NSObjectProtocol] = []
  private var batteryTimer: Timer?

  init(settings: AppSettings = .shared) {
    self.settings = settings
    surface = settings.islandSurfaceStyle
    glassLevel = settings.islandGlassLevel
    tinted = settings.islandGlassTinted
    clarity = settings.islandGlassClarity
    lightGlassInLightMode = settings.islandLightGlassInLightMode
    highlightHex = settings.islandHighlightHex
    windowTintHex = settings.islandWindowTintHex
    progressiveBlur = settings.islandProgressiveBlur
    lowBatteryEnabled = settings.islandLowBatteryMode
  }

  /// A fixed theme for previews and render tests; nothing is persisted.
  init(
    surface: IslandSurfaceStyle, glassLevel: Double = 0.5, tinted: Bool = true, clarity: Double = 0.5,
    light: Bool = false, lightGlass: Bool = true, highlightHex: String = "", windowTintHex: String = "",
    progressiveBlur: Bool = false, lowBattery: Bool = false
  ) {
    settings = AppSettings(defaults: UserDefaults(suiteName: "qs-theme-preview") ?? .standard)
    self.surface = surface
    self.glassLevel = glassLevel
    self.tinted = tinted
    self.clarity = clarity
    lightGlassInLightMode = lightGlass
    self.highlightHex = highlightHex
    self.windowTintHex = windowTintHex
    self.progressiveBlur = progressiveBlur
    lowBatteryEnabled = true
    lowBatteryActive = lowBattery
    systemIsLight = light
  }

  // MARK: Derived look

  /// What actually paints: low-battery mode forces plain black.
  var effectiveSurface: IslandSurfaceStyle { lowBatteryActive ? .black : surface }
  /// Pale frosted glass: Light appearance, the option on, and a glass surface in force.
  var usesLightGlass: Bool { systemIsLight && lightGlassInLightMode && effectiveSurface.usesGlass }
  var highlight: Color? { IslandHex.color(highlightHex) }
  var windowTint: Color? { IslandHex.color(windowTintHex) }
  var showsProgressiveBlur: Bool { progressiveBlur && !lowBatteryActive }

  // MARK: Writes

  func setSurface(_ next: IslandSurfaceStyle) {
    surface = next
    settings.islandSurfaceStyle = next
  }

  func setGlassLevel(_ next: Double) {
    glassLevel = min(1, max(0, next))
    settings.islandGlassLevel = glassLevel
  }

  func setTinted(_ next: Bool) {
    tinted = next
    settings.islandGlassTinted = next
  }

  func setClarity(_ next: Double) {
    clarity = min(1, max(0, next))
    settings.islandGlassClarity = clarity
  }

  func setLightGlass(_ next: Bool) {
    lightGlassInLightMode = next
    settings.islandLightGlassInLightMode = next
  }

  func setHighlight(_ hex: String) {
    highlightHex = hex
    settings.islandHighlightHex = hex
  }

  func setWindowTint(_ hex: String) {
    windowTintHex = hex
    settings.islandWindowTintHex = hex
  }

  func setProgressiveBlur(_ next: Bool) {
    progressiveBlur = next
    settings.islandProgressiveBlur = next
  }

  func setLowBattery(_ next: Bool) {
    lowBatteryEnabled = next
    settings.islandLowBatteryMode = next
    refreshPower()
  }

  // MARK: Environment monitoring

  /// Follows Light/Dark appearance, Low Power Mode and the battery level. Idempotent.
  func startMonitoring() {
    guard monitors.isEmpty, distributedMonitors.isEmpty else { return }
    refreshAppearance()
    refreshPower()
    distributedMonitors.append(
      DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.refreshAppearance() } })
    monitors.append(
      NotificationCenter.default.addObserver(
        forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.refreshPower() } })
    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPower() }
    }
    RunLoop.main.add(timer, forMode: .common)
    batteryTimer = timer
  }

  func stopMonitoring() {
    distributedMonitors.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    monitors.forEach { NotificationCenter.default.removeObserver($0) }
    distributedMonitors.removeAll()
    monitors.removeAll()
    batteryTimer?.invalidate()
    batteryTimer = nil
  }

  private func refreshAppearance() {
    let light = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == nil
    if light != systemIsLight { systemIsLight = light }
  }

  private func refreshPower() {
    let battery = SystemStatsReaders.battery()
    let active = LowBatteryPolicy.isActive(
      enabled: lowBatteryEnabled, percent: battery?.percent, charging: battery?.charging ?? true,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    if active != lowBatteryActive { lowBatteryActive = active }
  }
}

/// Where the shell's black melts into glass, as gradient stops over the shell's height.
/// Pure math so the look can be tested without rendering.
struct DynamicGlassMelt: Equatable {
  struct Stop: Equatable {
    let location: CGFloat
    let blackOpacity: Double
  }

  private(set) var stops: [Stop]

  /// - Parameters:
  ///   - height: the shell's current height.
  ///   - solidHeight: the band that must stay black (camera housing plus a little air).
  ///   - level: 0 keeps the island mostly black, 1 shows the most glass.
  ///   - lightness: 1 thins the black below the camera band for pale Light-mode glass.
  init(style: IslandSurfaceStyle, height: CGFloat, solidHeight: CGFloat, level: Double, lightness: Double = 0) {
    let level = min(1, max(0, level))
    let housing = min(0.9, max(0, solidHeight / max(1, height)))
    switch style {
    case .black:
      stops = [Stop(location: 0, blackOpacity: 1), Stop(location: 1, blackOpacity: 1)]
    case .liquidGlass:
      let fade = min(1, housing + 0.14)
      stops = housing > 0
        ? [Stop(location: 0, blackOpacity: 1), Stop(location: housing, blackOpacity: 1),
           Stop(location: fade, blackOpacity: 0), Stop(location: 1, blackOpacity: 0)]
        : [Stop(location: 0, blackOpacity: 0), Stop(location: 1, blackOpacity: 0)]
    case .dynamicGlass:
      // More glass pulls the solid stop up and thins the black at the bottom edge.
      let solid = min(0.92, housing + CGFloat(1 - level) * 0.34)
      let middle = solid + (1 - solid) * 0.5
      let bottom = 0.06 + 0.42 * (1 - level)
      stops = [
        Stop(location: 0, blackOpacity: 1), Stop(location: solid, blackOpacity: 1),
        Stop(location: middle, blackOpacity: 0.55 + 0.35 * (1 - level)),
        Stop(location: 1, blackOpacity: bottom),
      ]
    }
    guard lightness > 0 else { return }
    stops = stops.map { stop in
      stop.blackOpacity >= 1 ? stop : Stop(location: stop.location, blackOpacity: stop.blackOpacity * (1 - 0.5 * lightness))
    }
  }

  var gradient: Gradient {
    Gradient(stops: stops.map { .init(color: .black.opacity($0.blackOpacity), location: $0.location) })
  }
}

/// A wallpaper standing in for the window server's backdrop, so render tests can show the glass.
/// The real island never sets this; it blurs the live desktop with `NSVisualEffectView`.
struct IslandBackdropSnapshot {
  static let coordinateSpace = "islandBackdropCanvas"
  let image: NSImage
  let canvasSize: CGSize
}

private struct IslandBackdropSnapshotKey: EnvironmentKey {
  static let defaultValue: IslandBackdropSnapshot? = nil
}

extension EnvironmentValues {
  var islandBackdropSnapshot: IslandBackdropSnapshot? {
    get { self[IslandBackdropSnapshotKey.self] }
    set { self[IslandBackdropSnapshotKey.self] = newValue }
  }
}
