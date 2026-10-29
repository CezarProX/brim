import Foundation

/// Repeat state of a player. Apple Music has off/one/all (`song repeat`, code `pRpt`);
/// Spotify's AppleScript exposes only a boolean `repeating` (`pRep`), so it cycles off/all.
enum RepeatMode: String, Equatable, Sendable, CaseIterable {
  case off, one, all

  /// Four-char Apple Event enumerator for Apple Music's `eRpt`.
  var musicCode: String {
    switch self {
    case .off: return "kRpO"
    case .one: return "kRp1"
    case .all: return "kAll"
    }
  }

  init?(musicCode: String) {
    guard let mode = Self.allCases.first(where: { $0.musicCode == musicCode }) else { return nil }
    self = mode
  }

  /// Spotify's boolean: any repeat is "all"; it cannot repeat a single track.
  init(spotifyRepeating: Bool) { self = spotifyRepeating ? .all : .off }
  var spotifyRepeating: Bool { self != .off }

  /// What a tap does next: off, all, one, off. Players without "one" skip it.
  func next(supportsOne: Bool) -> RepeatMode {
    switch self {
    case .off: return .all
    case .all: return supportsOne ? .one : .off
    case .one: return .off
    }
  }

  var symbol: String { self == .one ? "repeat.1" : "repeat" }
  var isActive: Bool { self != .off }
  var title: String {
    switch self {
    case .off: return "Repeat off"
    case .one: return "Repeat one"
    case .all: return "Repeat all"
    }
  }

  static func supportsOne(_ source: NowPlayingSource) -> Bool { source == .music }
}
