// SystemIconLibrary.swift
// Brim
//
// Real Apple icons, read from the running system (never copied into the bundle): app icons such as
// Music or Clock, and the System Settings "graphic icons" (gear, battery, notifications...) that
// macOS declares as `com.apple.graphic-icon.*` types. Rendered once per size and cached; a source
// the system lacks returns nil so the caller can fall back to custom art.

import AppKit
import UniformTypeIdentifiers

/// Where a real Apple icon comes from.
enum SystemIconSource: Hashable, Sendable {
  /// An app bundle by path, e.g. `/System/Applications/Music.app`.
  case app(String)
  /// A System Settings graphic icon by type identifier, e.g. `com.apple.graphic-icon.gear`.
  case graphic(String)
  /// An app found by bundle identifier, for apps that live anywhere (Obsidian, Xcode...).
  case bundleID(String)

  /// Shorthand for an app in `/System/Applications`.
  static func systemApp(_ name: String) -> SystemIconSource { .app("/System/Applications/\(name).app") }
  /// Shorthand for an app in `/System/Applications/Utilities`.
  static func utility(_ name: String) -> SystemIconSource { .app("/System/Applications/Utilities/\(name).app") }
  /// Shorthand for a System Settings graphic icon.
  static func settings(_ name: String) -> SystemIconSource { .graphic("com.apple.graphic-icon.\(name)") }
}

/// The light/dark icon look the user picked in System Settings > Appearance (macOS 26 icon themes).
/// Real icons follow it on their own; custom icons read it so they match.
enum IconAppearance: Sendable {
  case light, dark

  /// Reads the global `AppleIconAppearanceTheme` ("RegularDark", "ClearLight", ...). Older systems
  /// have no themes and always draw colorful icons, so a missing value means light.
  static func resolve(theme: String?, interfaceStyle: String?) -> IconAppearance {
    guard let theme, !theme.isEmpty else { return .light }
    if theme.hasSuffix("Dark") { return .dark }
    if theme.hasSuffix("Light") { return .light }
    // Automatic themes follow the system's light/dark mode.
    return interfaceStyle == "Dark" ? .dark : .light
  }

  static var current: IconAppearance {
    let defaults = UserDefaults.standard
    return resolve(
      theme: defaults.string(forKey: "AppleIconAppearanceTheme"),
      interfaceStyle: defaults.string(forKey: "AppleInterfaceStyle"))
  }
}

@MainActor
enum SystemIconLibrary {
  private struct Key: Hashable {
    let source: SystemIconSource
    let pixels: Int
  }

  private static var rendered: [Key: CGImage] = [:]
  private static var icons: [SystemIconSource: NSImage] = [:]
  private static var missing: Set<SystemIconSource> = []

  /// The icon drawn at `pixels` × `pixels`, or nil when this Mac has no such icon.
  static func cgImage(for source: SystemIconSource, pixels: Int) -> CGImage? {
    let key = Key(source: source, pixels: max(16, pixels))
    if let hit = rendered[key] { return hit }
    guard let icon = icon(for: source) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: key.pixels, height: key.pixels)
    guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    rendered[key] = image
    return image
  }

  /// Whether the system provides this icon (checked once, then cached).
  static func isAvailable(_ source: SystemIconSource) -> Bool { icon(for: source) != nil }

  private static func icon(for source: SystemIconSource) -> NSImage? {
    if let hit = icons[source] { return hit }
    if missing.contains(source) { return nil }
    let loaded = load(source)
    if let loaded { icons[source] = loaded } else { missing.insert(source) }
    return loaded
  }

  private static func load(_ source: SystemIconSource) -> NSImage? {
    let workspace = NSWorkspace.shared
    switch source {
    case .app(let path):
      guard FileManager.default.fileExists(atPath: path) else { return nil }
      return workspace.icon(forFile: path)
    case .graphic(let identifier):
      guard let type = UTType(identifier), type.isDeclared else { return nil }
      return workspace.icon(for: type)
    case .bundleID(let identifier):
      guard let url = workspace.urlForApplication(withBundleIdentifier: identifier) else { return nil }
      return workspace.icon(forFile: url.path)
    }
  }
}
