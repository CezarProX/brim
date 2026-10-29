import SwiftUI

/// The live models the tiles read. Defaults to the app's shared instances; renders and tests inject fixtures.
@MainActor
struct CommandCenterModels {
  var playing: NowPlayingModel = .shared
  var stats: SystemStatsModel = .shared
  var awake: KeepAwakeModel = .shared
  var switches: MacSwitches = .shared
  var calendar: CalendarActivityModel = .shared
  /// Replaces the calendar agenda, for renders.
  var upcomingOverride: [CalendarAgendaItem]?
}

/// A tile's visible state, derived once so every size draws the same facts.
struct TileFacts: Equatable {
  var subtitle: String
  var isOn: Bool = false
  /// 0...1 ring for stat tiles.
  var level: Double?
  var value: String?

  @MainActor
  static func make(_ kind: TileKind, _ m: CommandCenterModels, now: Date = .now) -> TileFacts {
    switch kind {
    case .stayAwake:
      return TileFacts(subtitle: m.awake.isActive ? "On" : "Off", isOn: m.awake.isActive)
    case .darkMode:
      return TileFacts(subtitle: m.switches.darkMode ? "On" : "Off", isOn: m.switches.darkMode)
    case .desktopIcons:
      return TileFacts(subtitle: m.switches.desktopIconsVisible ? "Shown" : "Hidden", isOn: !m.switches.desktopIconsVisible)
    case .hiddenFiles:
      return TileFacts(subtitle: m.switches.hiddenFilesVisible ? "Shown" : "Hidden", isOn: m.switches.hiddenFilesVisible)
    case .islandVisibility:
      let on = AppSettings.shared.notchShelfEnabled
      return TileFacts(subtitle: on ? "Visible" : "Hidden", isOn: on)
    case .launcher:
      return TileFacts(subtitle: AppSettings.shared.thunderstormEnabled ? "Search" : "Off")
    case .cleaner:
      return TileFacts(subtitle: AppSettings.shared.cleanerEnabled ? "Uninstall" : "Off")
    case .menuBarManager:
      let manager = MenuBarManagerController.shared
      return TileFacts(subtitle: !manager.isRunning ? "Off" : (manager.isCollapsed ? "Hidden" : "Shown"), isOn: manager.isRunning && manager.isCollapsed)
    case .cpu:
      return TileFacts(subtitle: "Processor", level: m.stats.cpu, value: StatsCardReading.percent(m.stats.cpu))
    case .memory:
      let level = Double(m.stats.memoryUsed) / Double(max(1, m.stats.memoryTotal))
      return TileFacts(subtitle: gigabytes(Int64(m.stats.memoryUsed)) + " used", level: level, value: StatsCardReading.percent(level))
    case .disk:
      let level = m.stats.diskTotal > 0 ? 1 - Double(m.stats.diskFree) / Double(m.stats.diskTotal) : 0
      return TileFacts(subtitle: gigabytes(m.stats.diskFree) + " free",
                       level: level, value: StatsCardReading.percent(level))
    case .battery:
      guard let pct = m.stats.batteryPercent else { return TileFacts(subtitle: "No battery", value: "–") }
      return TileFacts(subtitle: m.stats.batteryCharging ? "Charging" : "On battery", level: Double(pct) / 100, value: "\(pct)%")
    case .network:
      return TileFacts(subtitle: "↑ " + NetworkMath.format(m.stats.networkUp), value: "↓ " + NetworkMath.format(m.stats.networkDown))
    default:
      return TileFacts(subtitle: "")
    }
  }

  /// "58 GB" / "1.2 TB": whole gigabytes keep the small tiles from truncating.
  private static func gigabytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    return gb >= 1000 ? String(format: "%.1f TB", gb / 1000) : "\(Int(gb.rounded())) GB"
  }

  /// The next event still ahead (or in progress), for the Up Next tile.
  @MainActor
  static func nextEvent(_ m: CommandCenterModels, now: Date = .now) -> CalendarAgendaItem? {
    let items = m.upcomingOverride ?? m.calendar.agenda.flatMap(\.items)
    return items.filter { $0.kind == .event && !$0.isAllDay && ($0.end ?? $0.start) > now }
      .min { $0.start < $1.start }
  }
}
