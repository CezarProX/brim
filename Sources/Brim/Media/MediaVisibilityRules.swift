import Foundation

struct BrowserWindowInfo: Equatable, Sendable {
  let title: String
  let isPrivate: Bool
}

/// Pure rules for hiding private-window media and applying the source allow-list.
enum MediaVisibilityRules {
  private static let privateMarkers = ["incognito", "inprivate", "private browsing", "private window"]

  /// Titles that browsers decorate on private windows ("... - Google Chrome (Incognito)",
  /// "Private Browsing — Firefox", "InPrivate - Microsoft Edge").
  static func titleLooksPrivate(_ title: String) -> Bool {
    let lower = title.lowercased()
    return privateMarkers.contains { lower.contains($0) }
  }

  /// Empty allow-list = everything is allowed.
  static func isSourceAllowed(bundleID: String, allowed: [String]) -> Bool {
    allowed.isEmpty || allowed.contains(bundleID)
  }

  /// The playing tab is private when a private window shows the track and no normal window does,
  /// or when every browser window is private. Nothing known about windows = not private (never hide by guess).
  static func isPrivateMedia(trackTitle: String, windows: [BrowserWindowInfo]) -> Bool {
    guard !windows.isEmpty else { return false }
    let privates = windows.filter(\.isPrivate)
    guard !privates.isEmpty else { return false }
    if privates.count == windows.count { return true }
    let needle = normalize(trackTitle)
    guard needle.count >= 3 else { return false }
    let inPrivate = privates.contains { normalize($0.title).contains(needle) }
    let inPublic = windows.filter { !$0.isPrivate }.contains { normalize($0.title).contains(needle) }
    return inPrivate && !inPublic
  }

  private static func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
