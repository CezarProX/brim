import Foundation

/// Termi-Notch settings. Disabled by default; no shell exists until the user opens the terminal.
extension AppSettings {
  var termiNotchEnabled: Bool {
    get { defaults.bool(forKey: "termiNotchEnabled") }
    set { defaults.set(newValue, forKey: "termiNotchEnabled") }
  }
  /// Default: ⌃` (Control + grave), the classic Quake-style key.
  var termiNotchShortcut: DropletShortcut {
    get { .load("termiNotch", fallback: DropletShortcut(keyCode: 50, modifiers: 4096), from: defaults) }
    set { newValue.save("termiNotch", to: defaults) }
  }
  /// 9...18.
  var termiNotchFontSize: Int {
    get { min(18, max(9, defaults.object(forKey: "termiNotchFontSize") as? Int ?? 12)) }
    set { defaults.set(min(18, max(9, newValue)), forKey: "termiNotchFontSize") }
  }
  /// "terminal", "iterm" or "warp".
  var termiNotchExternalApp: String {
    get { defaults.string(forKey: "termiNotchExternalApp") ?? "terminal" }
    set { defaults.set(newValue, forKey: "termiNotchExternalApp") }
  }
  /// Start new tabs in the folder of the current tab instead of the home folder.
  var termiNotchInheritFolder: Bool {
    get { defaults.object(forKey: "termiNotchInheritFolder") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "termiNotchInheritFolder") }
  }
}
