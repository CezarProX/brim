import Foundation

/// What clicking the menu-bar icon opens.
enum MenuBarClickStyle: String, CaseIterable, Identifiable, Sendable {
  case commandCenter, shortMenu
  var id: String { rawValue }
  var title: String { self == .commandCenter ? "Command Center" : "Short menu" }
}

/// Which page the Command Center opens on.
enum CommandCenterStartPage: String, CaseIterable, Identifiable, Sendable {
  case lastUsed, first
  var id: String { rawValue }
  var title: String { self == .lastUsed ? "Last used" : "First page" }
}

/// Optional live numbers shown beside the menu-bar icon.
enum MenuBarStatsReadout: String, CaseIterable, Identifiable, Sendable {
  case off, cpu, memory, network, battery
  var id: String { rawValue }
  var title: String {
    switch self {
    case .off: "Off"
    case .cpu: "CPU"
    case .memory: "Memory"
    case .network: "Network"
    case .battery: "Battery"
    }
  }
}

extension AppSettings {
  private enum CCKey {
    static let style = "menuBarClickStyle"
    static let layout = "commandCenterLayout"
    static let startPage = "commandCenterStartPage"
    static let lastPage = "commandCenterLastPage"
    static let closeAfterAction = "commandCenterCloseAfterAction"
    static let liveStatus = "menuBarLiveStatus"
    static let readout = "menuBarStatsReadout"
    static let showsSong = "menuBarShowsSong"
    static let onboardingDone = "onboardingCompleted"
  }

  var menuBarClickStyle: MenuBarClickStyle {
    get { MenuBarClickStyle(rawValue: defaults.string(forKey: CCKey.style) ?? "") ?? .commandCenter }
    set { defaults.set(newValue.rawValue, forKey: CCKey.style) }
  }
  /// Serialized tile layout (`kind@size,...`); nil means the default preset.
  var commandCenterLayout: String? {
    get { defaults.string(forKey: CCKey.layout) }
    set { defaults.set(newValue, forKey: CCKey.layout) }
  }
  var commandCenterStartPage: CommandCenterStartPage {
    get { CommandCenterStartPage(rawValue: defaults.string(forKey: CCKey.startPage) ?? "") ?? .lastUsed }
    set { defaults.set(newValue.rawValue, forKey: CCKey.startPage) }
  }
  var commandCenterLastPage: Int {
    get { max(0, defaults.integer(forKey: CCKey.lastPage)) }
    set { defaults.set(max(0, newValue), forKey: CCKey.lastPage) }
  }
  var commandCenterClosesAfterAction: Bool {
    get { defaults.object(forKey: CCKey.closeAfterAction) as? Bool ?? true }
    set { defaults.set(newValue, forKey: CCKey.closeAfterAction) }
  }
  /// The icon reflects music, a running timer, a recording or a working agent.
  var menuBarLiveStatus: Bool {
    get { defaults.object(forKey: CCKey.liveStatus) as? Bool ?? true }
    set { defaults.set(newValue, forKey: CCKey.liveStatus) }
  }
  var menuBarStatsReadout: MenuBarStatsReadout {
    get { MenuBarStatsReadout(rawValue: defaults.string(forKey: CCKey.readout) ?? "") ?? .off }
    set { defaults.set(newValue.rawValue, forKey: CCKey.readout) }
  }
  var menuBarShowsSong: Bool {
    get { defaults.object(forKey: CCKey.showsSong) as? Bool ?? false }
    set { defaults.set(newValue, forKey: CCKey.showsSong) }
  }
  var onboardingCompleted: Bool {
    get { defaults.bool(forKey: CCKey.onboardingDone) }
    set { defaults.set(newValue, forKey: CCKey.onboardingDone) }
  }
}
