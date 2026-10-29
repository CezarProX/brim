import Foundation

/// Typed keys for the coding-agent HUD (per-agent toggles, usage limits and alerts) and meeting controls.
extension AppSettings {
  private enum AgentKey {
    static func enabled(_ id: String) -> String { "agents.enabled.\(id)" }
    static let claudeLimit = "agents.usage.claudeTokenLimit"
    static let usageRing = "agents.usage.showRing"
    static let usageAlerts = "agents.usage.alerts"
    static let attentionFlash = "agents.attention.flash"
    static let micHotkey = "meetings.muteAllHotkeyEnabled"
    static let micHotkeyCode = "meetings.muteAllHotkeyCode"
    static let micHotkeyMods = "meetings.muteAllHotkeyMods"
    static let shortcutFallback = "meetings.appShortcutFallback"
  }

  /// Rolling 5-hour token budget the Claude Code usage ring is measured against.
  static let defaultClaudeTokenLimit = 2_000_000

  func agentEnabled(_ id: String) -> Bool {
    defaults.object(forKey: AgentKey.enabled(id)) as? Bool ?? true
  }

  func setAgentEnabled(_ id: String, _ value: Bool) { defaults.set(value, forKey: AgentKey.enabled(id)) }

  /// Anthropic doesn't publish plan limits locally, so the Claude ring stays off until the user sets one.
  var hasClaudeTokenLimit: Bool { defaults.integer(forKey: AgentKey.claudeLimit) > 0 }

  var claudeTokenLimit: Int {
    get {
      let stored = defaults.integer(forKey: AgentKey.claudeLimit)
      return stored > 0 ? stored : Self.defaultClaudeTokenLimit
    }
    set { defaults.set(max(10_000, newValue), forKey: AgentKey.claudeLimit) }
  }

  var agentUsageRingEnabled: Bool {
    get { defaults.object(forKey: AgentKey.usageRing) as? Bool ?? true }
    set { defaults.set(newValue, forKey: AgentKey.usageRing) }
  }

  var agentUsageAlertsEnabled: Bool {
    get { defaults.object(forKey: AgentKey.usageAlerts) as? Bool ?? true }
    set { defaults.set(newValue, forKey: AgentKey.usageAlerts) }
  }

  var agentAttentionFlashEnabled: Bool {
    get { defaults.object(forKey: AgentKey.attentionFlash) as? Bool ?? true }
    set { defaults.set(newValue, forKey: AgentKey.attentionFlash) }
  }

  var muteAllMicsHotkeyEnabled: Bool {
    get { defaults.object(forKey: AgentKey.micHotkey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: AgentKey.micHotkey) }
  }

  /// Virtual key code for the mute-all-microphones shortcut. Default: M (46).
  var muteAllMicsKeyCode: Int {
    get { defaults.object(forKey: AgentKey.micHotkeyCode) as? Int ?? 46 }
    set { defaults.set(newValue, forKey: AgentKey.micHotkeyCode) }
  }

  /// Carbon modifier mask. Default: control + option (4096 | 2048).
  var muteAllMicsModifiers: Int {
    get { defaults.object(forKey: AgentKey.micHotkeyMods) as? Int ?? 6144 }
    set { defaults.set(newValue, forKey: AgentKey.micHotkeyMods) }
  }

  /// Send the call app's own keyboard shortcut when its control can't be pressed through Accessibility.
  var meetingShortcutFallbackEnabled: Bool {
    get { defaults.object(forKey: AgentKey.shortcutFallback) as? Bool ?? true }
    set { defaults.set(newValue, forKey: AgentKey.shortcutFallback) }
  }
}
