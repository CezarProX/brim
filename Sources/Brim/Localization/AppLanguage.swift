// AppLanguage.swift
// Brim
//
// The user's language choice (System / English / Română). It is stored in AppSettings and mirrored to
// `AppleLanguages`, which is what Foundation reads when the app launches, so a change applies after a
// relaunch. English is the development language and the fallback for any string without a translation.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case english = "en"
  case romanian = "ro"

  var id: String { rawValue }

  /// Shown in the picker. Language names stay in their own language so they are findable.
  var displayName: String {
    switch self {
    case .system: String(localized: "System")
    case .english: "English"
    case .romanian: "Română"
    }
  }

  /// Languages the bundle ships a Localizable.strings for.
  static let supportedCodes: [String] = ["en", "ro"]

  /// The `AppleLanguages` value for this choice, or nil to follow the system.
  var appleLanguages: [String]? {
    switch self {
    case .system: nil
    case .english, .romanian: [rawValue]
    }
  }

  /// Picks the best shipped language for the system's preferred list; English when none match.
  static func resolve(preferred: [String]) -> String {
    for entry in preferred {
      let code = entry.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
      if supportedCodes.contains(code) { return code }
    }
    return "en"
  }
}

extension AppSettings {
  private static let appLanguageKey = "appLanguage"

  var appLanguage: AppLanguage {
    get { AppLanguage(rawValue: defaults.string(forKey: Self.appLanguageKey) ?? "") ?? .system }
    set {
      defaults.set(newValue.rawValue, forKey: Self.appLanguageKey)
      Self.applyLanguageOverride(newValue, to: defaults)
    }
  }

  /// Writes (or clears) the per-app `AppleLanguages` override that Foundation honours at next launch.
  static func applyLanguageOverride(_ language: AppLanguage, to defaults: UserDefaults) {
    if let codes = language.appleLanguages {
      defaults.set(codes, forKey: "AppleLanguages")
    } else {
      defaults.removeObject(forKey: "AppleLanguages")
    }
  }
}
