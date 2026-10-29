import Foundation

/// How the open island's shell is painted (Settings > Theming).
enum IslandSurfaceStyle: String, CaseIterable, Identifiable, Sendable {
  /// Solid black, like the hardware notch.
  case black
  /// Black at the top melting into blurred, tinted glass toward the bottom (the default).
  case dynamicGlass
  /// Glass from edge to edge; only the band behind the camera stays black.
  case liquidGlass

  var id: String { rawValue }

  var title: String {
    switch self {
    case .black: "Black"
    case .dynamicGlass: "Dynamic Glass"
    case .liquidGlass: "Liquid Glass"
    }
  }

  var usesGlass: Bool { self != .black }
}

/// Typed keys for the island's surface, glass level and tint.
extension AppSettings {
  private enum ThemingKey {
    static let surface = "islandSurfaceStyle"
    static let glassLevel = "islandGlassLevel"
    static let tinted = "islandGlassTinted"
  }

  /// Older builds stored a single glass on/off switch; off still means black.
  var islandSurfaceStyle: IslandSurfaceStyle {
    get {
      if let raw = defaults.string(forKey: ThemingKey.surface), let style = IslandSurfaceStyle(rawValue: raw) {
        return style
      }
      return islandGlassEnabled ? .dynamicGlass : .black
    }
    set {
      defaults.set(newValue.rawValue, forKey: ThemingKey.surface)
      islandGlassEnabled = newValue.usesGlass
    }
  }

  /// Where black melts into glass: 0 keeps most of the island black, 1 shows the most glass.
  var islandGlassLevel: Double {
    get { min(1, max(0, defaults.object(forKey: ThemingKey.glassLevel) as? Double ?? 0.5)) }
    set { defaults.set(min(1, max(0, newValue)), forKey: ThemingKey.glassLevel) }
  }

  /// Tinted glass darkens what shows through so text stays readable on any wallpaper; off is clear glass.
  var islandGlassTinted: Bool {
    get { defaults.object(forKey: ThemingKey.tinted) as? Bool ?? true }
    set { defaults.set(newValue, forKey: ThemingKey.tinted) }
  }
}
