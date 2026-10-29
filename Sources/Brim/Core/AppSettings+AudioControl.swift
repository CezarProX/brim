import Foundation

extension AppSettings {
  private enum AudioKey {
    static let rememberVolumes = "audioRememberVolumes"
    static let showPaused = "audioShowPausedApps"
    static let includeSystem = "audioIncludeSystemSounds"
    static let curve = "audioVolumeCurve"
    static let allowBoost = "audioAllowBoost"
    static let saved = "audioSavedAppVolumes"
    static let preferredEnabled = "audioPreferredDevicesEnabled"
    static let preferredOut = "audioPreferredOutputUIDs"
    static let preferredIn = "audioPreferredInputUIDs"
  }

  private func audioBool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

  var audioRememberVolumes: Bool {
    get { audioBool(AudioKey.rememberVolumes, true) }
    set { defaults.set(newValue, forKey: AudioKey.rememberVolumes) }
  }
  var audioShowPausedApps: Bool {
    get { audioBool(AudioKey.showPaused, false) }
    set { defaults.set(newValue, forKey: AudioKey.showPaused) }
  }
  var audioIncludeSystemSounds: Bool {
    get { audioBool(AudioKey.includeSystem, false) }
    set { defaults.set(newValue, forKey: AudioKey.includeSystem) }
  }
  var audioVolumeCurve: VolumeCurve {
    get { VolumeCurve(rawValue: defaults.string(forKey: AudioKey.curve) ?? "") ?? .natural }
    set { defaults.set(newValue.rawValue, forKey: AudioKey.curve) }
  }
  /// Lets sliders go past 100% (to 200%). Off by default: boosting can distort.
  var audioAllowBoost: Bool {
    get { audioBool(AudioKey.allowBoost, false) }
    set { defaults.set(newValue, forKey: AudioKey.allowBoost) }
  }
  var preferredDevicesEnabled: Bool {
    get { audioBool(AudioKey.preferredEnabled, false) }
    set { defaults.set(newValue, forKey: AudioKey.preferredEnabled) }
  }
  var preferredOutputUIDs: [String] {
    get { defaults.stringArray(forKey: AudioKey.preferredOut) ?? [] }
    set { defaults.set(newValue, forKey: AudioKey.preferredOut) }
  }
  var preferredInputUIDs: [String] {
    get { defaults.stringArray(forKey: AudioKey.preferredIn) ?? [] }
    set { defaults.set(newValue, forKey: AudioKey.preferredIn) }
  }
  /// Remembered per-app settings, keyed by bundle id.
  var audioSavedAppSettings: [String: SavedAppAudio] {
    get {
      guard let data = defaults.data(forKey: AudioKey.saved),
            let value = try? JSONDecoder().decode([String: SavedAppAudio].self, from: data) else { return [:] }
      return value
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: AudioKey.saved) }
    }
  }
}

/// What "Remember volumes" stores for one app.
struct SavedAppAudio: Codable, Equatable, Sendable {
  var slider: Double
  var muted: Bool
  /// Output device uid; nil follows the system default.
  var outputUID: String?
}
