import Foundation

/// The three sizes of the floating "Liquid Player".
enum LiquidPlayerSize: String, CaseIterable, Identifiable, Sendable {
  case mini, player, expanded
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

extension AppSettings {
  private enum LiquidKey {
    static let popOut = "liquidPlayerDragPopsOut"
    static let size = "liquidPlayerSize"
    static let origin = "liquidPlayerOrigin"
    static let floatOverApps = "liquidPlayerFloatOverApps"
    static let menuBar = "liquidPlayerMenuBarMode"
    static let menuBarSong = "liquidPlayerMenuBarSong"
    static let autoHide = "liquidPlayerAutoHide"
  }

  private func liquidBool(_ key: String, _ fallback: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? fallback
  }

  /// "Dragging the notch player: pops out to floating" (off = stays in the notch).
  var notchPlayerDragPopsOut: Bool {
    get { liquidBool(LiquidKey.popOut, true) }
    set { defaults.set(newValue, forKey: LiquidKey.popOut) }
  }
  var liquidPlayerSize: LiquidPlayerSize {
    get { LiquidPlayerSize(rawValue: defaults.string(forKey: LiquidKey.size) ?? "") ?? .player }
    set { defaults.set(newValue.rawValue, forKey: LiquidKey.size) }
  }
  /// Top-left corner of the floating window in screen coordinates, "x,y"; nil = default spot.
  var liquidPlayerOrigin: CGPoint? {
    get {
      let parts = (defaults.string(forKey: LiquidKey.origin) ?? "").split(separator: ",").compactMap { Double($0) }
      return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
    set { defaults.set(newValue.map { "\(Int($0.x)),\(Int($0.y))" }, forKey: LiquidKey.origin) }
  }
  /// On: floats above every app. Off: stays at desktop level, behind app windows.
  var liquidPlayerFloatsOverApps: Bool {
    get { liquidBool(LiquidKey.floatOverApps, true) }
    set { defaults.set(newValue, forKey: LiquidKey.floatOverApps) }
  }
  /// A menu-bar item shows the song; clicking it drops the player down.
  var liquidPlayerMenuBarMode: Bool {
    get { liquidBool(LiquidKey.menuBar, false) }
    set { defaults.set(newValue, forKey: LiquidKey.menuBar) }
  }
  var liquidPlayerShowsSongInMenuBar: Bool {
    get { liquidBool(LiquidKey.menuBarSong, true) }
    set { defaults.set(newValue, forKey: LiquidKey.menuBarSong) }
  }
  /// The menu-bar drop-down hides itself 3 seconds after the pointer leaves it.
  var liquidPlayerAutoHides: Bool {
    get { liquidBool(LiquidKey.autoHide, true) }
    set { defaults.set(newValue, forKey: LiquidKey.autoHide) }
  }
}
