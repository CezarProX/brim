import Foundation

/// Settings for mirroring macOS notifications into the island. Everything defaults to off.
extension AppSettings {
  /// Master switch. Turning it on is what triggers the Accessibility prompt.
  var notificationHUDEnabled: Bool {
    get { defaults.bool(forKey: "notificationHUDEnabled") }
    set { defaults.set(newValue, forKey: "notificationHUDEnabled") }
  }

  /// Close the macOS banner after capturing it (best effort, via Accessibility).
  var notificationHUDHideBanner: Bool {
    get { defaults.bool(forKey: "notificationHUDHideBanner") }
    set { defaults.set(newValue, forKey: "notificationHUDHideBanner") }
  }

  /// Read the usernoted database instead of the banner. Needs Full Disk Access.
  var notificationHUDUsernotedFallback: Bool {
    get { defaults.bool(forKey: "notificationHUDUsernotedFallback") }
    set { defaults.set(newValue, forKey: "notificationHUDUsernotedFallback") }
  }

  var notificationHUDShowBody: Bool {
    get { defaults.object(forKey: "notificationHUDShowBody") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "notificationHUDShowBody") }
  }

  var notificationHUDHideWhileSharing: Bool {
    get { defaults.object(forKey: "notificationHUDHideWhileSharing") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "notificationHUDHideWhileSharing") }
  }

  /// Seconds a card stays before it dismisses itself.
  var notificationHUDDuration: Double {
    get {
      let value = defaults.object(forKey: "notificationHUDDuration") as? Double ?? 6
      return min(max(value, 2), 20)
    }
    set { defaults.set(newValue, forKey: "notificationHUDDuration") }
  }

  /// Bundle ids or app names that never appear in the island.
  var notificationHUDDeniedApps: [String] {
    get { defaults.stringArray(forKey: "notificationHUDDeniedApps") ?? [] }
    set { defaults.set(newValue, forKey: "notificationHUDDeniedApps") }
  }

  /// When non-empty, only these apps appear.
  var notificationHUDAllowedApps: [String] {
    get { defaults.stringArray(forKey: "notificationHUDAllowedApps") ?? [] }
    set { defaults.set(newValue, forKey: "notificationHUDAllowedApps") }
  }
}
