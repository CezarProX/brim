import Foundation

/// AppleScript sources for the Apple Music "Add to Playlist" control. Pure string building so the
/// quoting rules are testable; only `MusicPlaylistsModel` runs them (and only on a user tap).
enum MusicPlaylistScripts {
  /// Escapes a value for use inside an AppleScript string literal.
  static func literal(_ value: String) -> String {
    var out = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\\": out += "\\\\"
      case "\"": out += "\\\""
      case "\n", "\r", "\t": out += " "
      default:
        if scalar.value < 0x20 { continue }
        out.unicodeScalars.append(scalar)
      }
    }
    return out
  }

  /// Names of the playlists a track can be added to: user-made, not smart, not a system list.
  static let listPlaylists = """
    tell application "Music" to get name of every user playlist whose smart is false and special kind is none
    """

  static func addCurrentTrack(to playlist: String) -> String {
    "tell application \"Music\" to duplicate current track to user playlist \"\(literal(playlist))\""
  }

  /// Names to offer, in source order, without blanks or duplicates, capped for the menu.
  static func cleaned(_ names: [String], limit: Int = 40) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for raw in names {
      let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, seen.insert(name).inserted else { continue }
      result.append(String(name.prefix(120)))
      if result.count == limit { break }
    }
    return result
  }
}
