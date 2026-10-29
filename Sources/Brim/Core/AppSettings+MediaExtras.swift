import Foundation

/// What a click on the notch does while music is playing.
enum NotchMusicClickAction: String, CaseIterable, Identifiable, Sendable {
  case openIsland, playPause, openMusicApp
  var id: String { rawValue }
  var title: String {
    switch self {
    case .openIsland: return "Open the island"
    case .playPause: return "Play / pause"
    case .openMusicApp: return "Open the music app"
    }
  }
}

extension AppSettings {
  private enum ExtraKey {
    static let hidePrivate = "mediaHidePrivateBrowsing"
    static let allowedSources = "mediaAllowedSourceBundleIDs"
    static let automix = "mediaAutomixIndicator"
    static let qualityBadge = "mediaQualityBadge"
    static let discord = "mediaDiscordPresence"
    static let discordClientID = "mediaDiscordClientID"
    static let hideOnPause = "mediaHideOnPauseMinutes"
    static let spacebar = "mediaSpacebarPlayPause"
    static let clickAction = "mediaNotchClickAction"
  }

  private func extraBool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

  var mediaHidePrivateBrowsing: Bool {
    get { extraBool(ExtraKey.hidePrivate, true) }
    set { defaults.set(newValue, forKey: ExtraKey.hidePrivate) }
  }
  /// Bundle ids allowed to show media in the island; empty means every source.
  var mediaAllowedSources: [String] {
    get { defaults.stringArray(forKey: ExtraKey.allowedSources) ?? [] }
    set { defaults.set(newValue, forKey: ExtraKey.allowedSources) }
  }
  var mediaAutomixIndicator: Bool {
    get { extraBool(ExtraKey.automix, true) }
    set { defaults.set(newValue, forKey: ExtraKey.automix) }
  }
  /// Reads the track's format from Music (Automation permission it already has).
  var mediaQualityBadge: Bool {
    get { extraBool(ExtraKey.qualityBadge, true) }
    set { defaults.set(newValue, forKey: ExtraKey.qualityBadge) }
  }
  /// Off by default: it tells Discord (running locally) what you are listening to.
  var discordPresenceEnabled: Bool {
    get { extraBool(ExtraKey.discord, false) }
    set { defaults.set(newValue, forKey: ExtraKey.discord) }
  }
  var discordClientID: String {
    get { defaults.string(forKey: ExtraKey.discordClientID) ?? "" }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: ExtraKey.discordClientID) }
  }
  /// Minutes a paused song keeps its place in the island; 0 keeps it until playback is gone.
  var mediaHideOnPauseMinutes: Int {
    get { defaults.object(forKey: ExtraKey.hideOnPause) as? Int ?? 10 }
    set { defaults.set(max(0, newValue), forKey: ExtraKey.hideOnPause) }
  }
  var mediaSpacebarPlayPause: Bool {
    get { extraBool(ExtraKey.spacebar, true) }
    set { defaults.set(newValue, forKey: ExtraKey.spacebar) }
  }
  var notchMusicClickAction: NotchMusicClickAction {
    get { NotchMusicClickAction(rawValue: defaults.string(forKey: ExtraKey.clickAction) ?? "") ?? .openIsland }
    set { defaults.set(newValue.rawValue, forKey: ExtraKey.clickAction) }
  }
}
