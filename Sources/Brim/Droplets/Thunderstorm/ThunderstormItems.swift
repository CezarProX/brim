import AppKit
import Foundation

/// A user URL template: "gh swift" with keyword `gh` opens the template with `{query}` filled in.
struct ThunderQuicklink: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var keyword: String
  var name: String
  var template: String

  static let samples = [
    ThunderQuicklink(keyword: "gh", name: "Search GitHub", template: "https://github.com/search?q={query}"),
    ThunderQuicklink(keyword: "yt", name: "Search YouTube", template: "https://www.youtube.com/results?search_query={query}"),
    ThunderQuicklink(keyword: "maps", name: "Search Maps", template: "https://maps.apple.com/?q={query}"),
  ]

  private static let blockedSchemes: Set<String> = ["file", "javascript", "data", "vbscript"]

  /// The address with `{query}` percent-encoded in; nil when the result is not a safe URL.
  static func expand(_ template: String, query: String) -> URL? {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?/:"))
    let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    let text = template.replacingOccurrences(of: "{query}", with: encoded)
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), !blockedSchemes.contains(scheme),
      url.host != nil || scheme == "mailto" || scheme == "tel"
    else { return nil }
    return url
  }

  /// When `input` starts with this keyword and a space, the rest is the query.
  func query(from input: String) -> String? {
    let key = keyword.lowercased()
    guard !key.isEmpty else { return nil }
    let lowered = input.lowercased()
    guard lowered == key || lowered.hasPrefix(key + " ") else { return nil }
    return String(input.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
  }
}

/// Text expansion: choose it in the launcher and the text is pasted into the app you were in.
struct ThunderSnippet: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var keyword: String
  var title: String
  var text: String

  /// Fills `{date}`, `{time}` and `{clipboard}`.
  func expanded(now: Date = .now, clipboard: String = "") -> String {
    let date = DateFormatter()
    date.dateStyle = .medium
    date.timeStyle = .none
    let time = DateFormatter()
    time.dateStyle = .none
    time.timeStyle = .short
    return text.replacingOccurrences(of: "{date}", with: date.string(from: now))
      .replacingOccurrences(of: "{time}", with: time.string(from: now))
      .replacingOccurrences(of: "{clipboard}", with: clipboard)
  }
}

enum ThunderSystemCommand: String, CaseIterable, Identifiable, Sendable {
  case sleepDisplay, lockScreen, emptyTrash, toggleDarkMode

  var id: String { rawValue }
  var title: String {
    switch self {
    case .sleepDisplay: "Sleep Display"
    case .lockScreen: "Lock Screen"
    case .emptyTrash: "Empty Trash"
    case .toggleDarkMode: "Toggle Dark Mode"
    }
  }
  var symbol: String {
    switch self {
    case .sleepDisplay: "display"
    case .lockScreen: "lock.fill"
    case .emptyTrash: "trash.fill"
    case .toggleDarkMode: "circle.lefthalf.filled"
    }
  }
  var keywords: String {
    switch self {
    case .sleepDisplay: "screen off turn off display monitor"
    case .lockScreen: "lock mac secure"
    case .emptyTrash: "bin delete garbage"
    case .toggleDarkMode: "appearance theme light dark"
    }
  }
  /// Destructive commands ask once more before they run.
  var needsConfirmation: Bool { self == .emptyTrash }
}

/// What activating a row does.
enum ThunderAction: Equatable {
  case open(URL)
  case openApp(URL)
  case copy(String)
  case paste(String)
  case system(ThunderSystemCommand)
  case clipboardEntry(UUID)
}

struct ThunderResult: Identifiable, Equatable {
  enum Kind: String { case calculator, conversion, app, file, clipboard, quicklink, snippet, system, web }

  let id: String
  let kind: Kind
  let title: String
  var subtitle: String = ""
  var symbol: String
  var iconPath: String?
  let action: ThunderAction

  var hint: String {
    switch kind {
    case .calculator, .conversion: "Copy"
    case .snippet: "Insert"
    case .clipboard: "Copy"
    case .system: "Run"
    case .web, .quicklink: "Open"
    case .app, .file: "Open"
    }
  }
}
