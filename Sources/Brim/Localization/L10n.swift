// L10n.swift
// Brim
//
// One lookup point for user-facing copy that is not a SwiftUI literal (menu items, alerts, HUD text
// built in code). English is the key, so a missing translation falls back to English by itself.

import Foundation

enum L10n {
  /// The bundle that holds the .lproj folders. Tests point this at a specific language folder.
  nonisolated(unsafe) static var bundle: Bundle = .main

  /// Looks `key` up in Localizable.strings; returns the key itself when there is no entry.
  static func tr(_ key: String) -> String {
    bundle.localizedString(forKey: key, value: key, table: nil)
  }

  /// `tr` with printf-style arguments, for keys such as "Page %lld of %lld".
  static func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: Locale.current, arguments: arguments)
  }
}
