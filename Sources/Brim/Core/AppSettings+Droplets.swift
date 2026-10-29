import Carbon.HIToolbox
import Foundation

/// Typed keys for the Droplets: Emoji Picker, LocalSend, MCP, Xcode Builds and Stay Awake.
/// (The Action Ring keys live next to `RingLayout`.)
extension AppSettings {
  private func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
  private func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }

  // MARK: Emoji Picker
  var emojiPickerEnabled: Bool {
    get { bool("emojiPickerEnabled", false) }
    set { defaults.set(newValue, forKey: "emojiPickerEnabled") }
  }
  var emojiHotkeyCode: Int {
    get { int("emojiHotkeyCode", kVK_ANSI_E) }
    set { defaults.set(newValue, forKey: "emojiHotkeyCode") }
  }
  var emojiHotkeyModifiers: Int {
    get { int("emojiHotkeyModifiers", optionKey | cmdKey) }
    set { defaults.set(newValue, forKey: "emojiHotkeyModifiers") }
  }
  var emojiHotkeyLabel: String {
    get { defaults.string(forKey: "emojiHotkeyLabel") ?? "E" }
    set { defaults.set(newValue, forKey: "emojiHotkeyLabel") }
  }
  var emojiColumns: Int {
    get { min(12, max(5, int("emojiColumns", 8))) }
    set { defaults.set(min(12, max(5, newValue)), forKey: "emojiColumns") }
  }
  var emojiSkinToneRaw: Int {
    get { min(5, max(0, int("emojiSkinTone", 0))) }
    set { defaults.set(min(5, max(0, newValue)), forKey: "emojiSkinTone") }
  }
  var emojiRecents: [String] {
    get { defaults.stringArray(forKey: "emojiRecents") ?? [] }
    set { defaults.set(newValue, forKey: "emojiRecents") }
  }

  // MARK: LocalSend
  var localSendEnabled: Bool {
    get { bool("localSendEnabled", false) }
    set { defaults.set(newValue, forKey: "localSendEnabled") }
  }
  var localSendReceiveEnabled: Bool {
    get { bool("localSendReceiveEnabled", false) }
    set { defaults.set(newValue, forKey: "localSendReceiveEnabled") }
  }
  var localSendAlias: String {
    get { defaults.string(forKey: "localSendAlias") ?? Host.current().localizedName ?? "Brim Mac" }
    set { defaults.set(String(newValue.prefix(40)), forKey: "localSendAlias") }
  }
  var localSendFingerprint: String {
    get {
      if let value = defaults.string(forKey: "localSendFingerprint") { return value }
      let value = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
      defaults.set(value, forKey: "localSendFingerprint")
      return value
    }
    set { defaults.set(newValue, forKey: "localSendFingerprint") }
  }

  // MARK: MCP
  var mcpEnabled: Bool {
    get { bool("mcpEnabled", false) }
    set { defaults.set(newValue, forKey: "mcpEnabled") }
  }
  /// Raw names of the MCP tools the user has allowed. Empty by default: everything is off.
  var mcpAllowedTools: Set<String> {
    get { Set(defaults.stringArray(forKey: "mcpAllowedTools") ?? []) }
    set { defaults.set(Array(newValue).sorted(), forKey: "mcpAllowedTools") }
  }

  // MARK: Xcode Builds
  var xcodeBuildsEnabled: Bool {
    get { bool("xcodeBuildsEnabled", false) }
    set { defaults.set(newValue, forKey: "xcodeBuildsEnabled") }
  }

  // MARK: Stay Awake
  var stayAwakeKeepDisplayOn: Bool {
    get { bool("stayAwakeKeepDisplayOn", true) }
    set { defaults.set(newValue, forKey: "stayAwakeKeepDisplayOn") }
  }
  var stayAwakeOnPowerAdapter: Bool {
    get { bool("stayAwakeOnPowerAdapter", false) }
    set { defaults.set(newValue, forKey: "stayAwakeOnPowerAdapter") }
  }
  var stayAwakeScheduleEnabled: Bool {
    get { bool("stayAwakeScheduleEnabled", false) }
    set { defaults.set(newValue, forKey: "stayAwakeScheduleEnabled") }
  }
  /// Minutes after midnight.
  var stayAwakeScheduleStart: Int {
    get { int("stayAwakeScheduleStart", 9 * 60) }
    set { defaults.set(newValue, forKey: "stayAwakeScheduleStart") }
  }
  var stayAwakeScheduleEnd: Int {
    get { int("stayAwakeScheduleEnd", 18 * 60) }
    set { defaults.set(newValue, forKey: "stayAwakeScheduleEnd") }
  }
  /// Weekday numbers 1 (Sunday) ... 7 (Saturday).
  var stayAwakeScheduleDays: Set<Int> {
    get { Set((defaults.array(forKey: "stayAwakeScheduleDays") as? [Int]) ?? [2, 3, 4, 5, 6]) }
    set { defaults.set(Array(newValue).sorted(), forKey: "stayAwakeScheduleDays") }
  }
  var stayAwakeLidClosedOnPower: Bool {
    get { bool("stayAwakeLidClosedOnPower", false) }
    set { defaults.set(newValue, forKey: "stayAwakeLidClosedOnPower") }
  }
}
