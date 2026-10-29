import Carbon.HIToolbox
import Foundation

/// Typed keys for the launcher (Thunderstorm), Cleaner and Menu Bar Manager droplets.
/// Everything is off by default; Cleaner has no shortcut, it is opened from its tile.
extension AppSettings {
  private func toolBool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

  // MARK: Thunderstorm
  var thunderstormEnabled: Bool {
    get { toolBool("thunderstormEnabled", false) }
    set { defaults.set(newValue, forKey: "thunderstormEnabled") }
  }
  var thunderstormShortcut: DropletShortcut {
    get {
      DropletShortcut.load("thunderstorm", fallback: DropletShortcut(keyCode: kVK_Space, modifiers: optionKey), from: defaults)
    }
    set { newValue.save("thunderstorm", to: defaults) }
  }
  var thunderstormSearchFiles: Bool {
    get { toolBool("thunderstormSearchFiles", true) }
    set { defaults.set(newValue, forKey: "thunderstormSearchFiles") }
  }
  var thunderstormSearchClipboard: Bool {
    get { toolBool("thunderstormSearchClipboard", true) }
    set { defaults.set(newValue, forKey: "thunderstormSearchClipboard") }
  }
  var thunderstormSystemCommands: Bool {
    get { toolBool("thunderstormSystemCommands", true) }
    set { defaults.set(newValue, forKey: "thunderstormSystemCommands") }
  }
  /// Web search address with `{query}`; the last row of every search.
  var thunderstormWebTemplate: String {
    get { defaults.string(forKey: "thunderstormWebTemplate") ?? "https://duckduckgo.com/?q={query}" }
    set { defaults.set(newValue, forKey: "thunderstormWebTemplate") }
  }
  var thunderstormQuicklinks: [ThunderQuicklink] {
    get { toolJSON("thunderstormQuicklinks") ?? ThunderQuicklink.samples }
    set { setToolJSON(newValue, "thunderstormQuicklinks") }
  }
  var thunderstormSnippets: [ThunderSnippet] {
    get { toolJSON("thunderstormSnippets") ?? [] }
    set { setToolJSON(newValue, "thunderstormSnippets") }
  }
  var thunderstormFrecency: [String: ThunderFrecency] {
    get { toolJSON("thunderstormFrecency") ?? [:] }
    set { setToolJSON(newValue, "thunderstormFrecency") }
  }

  // MARK: Cleaner
  var cleanerEnabled: Bool {
    get { toolBool("cleanerEnabled", false) }
    set { defaults.set(newValue, forKey: "cleanerEnabled") }
  }

  // MARK: Menu Bar Manager
  var menuBarManagerEnabled: Bool {
    get { toolBool("menuBarManagerEnabled", false) }
    set { defaults.set(newValue, forKey: "menuBarManagerEnabled") }
  }
  var menuBarManagerShortcut: DropletShortcut {
    get {
      DropletShortcut.load(
        "menuBarManager", fallback: DropletShortcut(keyCode: kVK_ANSI_B, modifiers: optionKey | cmdKey), from: defaults)
    }
    set { newValue.save("menuBarManager", to: defaults) }
  }
  var menuBarManagerAutoRehide: Bool {
    get { toolBool("menuBarManagerAutoRehide", true) }
    set { defaults.set(newValue, forKey: "menuBarManagerAutoRehide") }
  }
  var menuBarManagerRehideSeconds: Int {
    get { min(120, max(2, defaults.object(forKey: "menuBarManagerRehideSeconds") as? Int ?? 10)) }
    set { defaults.set(min(120, max(2, newValue)), forKey: "menuBarManagerRehideSeconds") }
  }
  var menuBarManagerStartCollapsed: Bool {
    get { toolBool("menuBarManagerStartCollapsed", true) }
    set { defaults.set(newValue, forKey: "menuBarManagerStartCollapsed") }
  }

  private func toolJSON<T: Decodable>(_ key: String) -> T? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  private func setToolJSON<T: Encodable>(_ value: T, _ key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }
}
