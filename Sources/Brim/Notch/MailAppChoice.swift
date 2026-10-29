import AppKit

/// Which mail app the Mail action uses. Apple Mail composes through the system sharing service with
/// the files attached. Other apps are handed the files with "open with"; whether that becomes an
/// attachment is up to the app.
enum MailAppChoice {
  static let appleMail = "com.apple.mail"

  struct App: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
  }

  enum Route: Equatable {
    case sharingService
    case openWith(bundleID: String)
  }

  /// Pure routing: an empty or no-longer-installed choice falls back to the sharing service.
  static func route(chosen: String, installed: Set<String>) -> Route {
    guard !chosen.isEmpty, chosen != appleMail, installed.contains(chosen) else { return .sharingService }
    return .openWith(bundleID: chosen)
  }

  /// Apps that claim `mailto:`, sorted by name.
  static func installed(workspace: NSWorkspace = .shared) -> [App] {
    guard let probe = URL(string: "mailto:") else { return [] }
    var seen = Set<String>()
    return workspace.urlsForApplications(toOpen: probe).compactMap { url -> App? in
      guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
      return App(bundleID: id, name: FileManager.default.displayName(atPath: url.path)
        .replacingOccurrences(of: ".app", with: ""))
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  @MainActor
  static func send(_ urls: [URL], chosen: String = AppSettings.shared.trayMailAppBundleID) {
    let apps = installed()
    switch route(chosen: chosen, installed: Set(apps.map(\.bundleID))) {
    case .sharingService:
      guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: urls) else {
        IslandFlashCenter.shared.show("Mail unavailable", symbol: "envelope.fill", tint: .white)
        return
      }
      service.perform(withItems: urls)
    case .openWith(let bundleID):
      guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
      NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
  }
}
