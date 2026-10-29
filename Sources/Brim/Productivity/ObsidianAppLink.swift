import AppKit
import Foundation

/// A vault the Obsidian app knows about, read from its own vault registry.
struct ObsidianKnownVault: Identifiable, Equatable {
  let path: String
  let lastOpened: Date
  let isOpen: Bool
  var id: String { path }
  var name: String { (path as NSString).lastPathComponent }
}

/// Talks to the installed Obsidian app: which vaults it has, whether it runs, and deep links into it.
enum ObsidianAppLink {
  static let bundleID = "md.obsidian"
  static let maxConfigBytes = 1_000_000

  /// Obsidian's vault registry (`{"vaults": {id: {path, ts, open}}}`).
  static var defaultConfigURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
  }

  /// Vaults that still exist on disk; the open one first, then most recently opened.
  static func knownVaults(configURL: URL = defaultConfigURL, fileManager: FileManager = .default) -> [ObsidianKnownVault] {
    guard let data = try? Data(contentsOf: configURL), data.count <= maxConfigBytes,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let vaults = json["vaults"] as? [String: Any]
    else { return [] }
    let parsed = vaults.values.compactMap { entry -> ObsidianKnownVault? in
      guard let entry = entry as? [String: Any], let path = entry["path"] as? String else { return nil }
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
      let millis = (entry["ts"] as? NSNumber)?.doubleValue ?? 0
      return ObsidianKnownVault(
        path: path, lastOpened: Date(timeIntervalSince1970: millis / 1000), isOpen: entry["open"] as? Bool ?? false)
    }
    return parsed.sorted {
      $0.isOpen != $1.isOpen ? $0.isOpen : ($0.lastOpened != $1.lastOpened ? $0.lastOpened > $1.lastOpened : $0.path < $1.path)
    }
  }

  static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

  static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

  /// `obsidian://open?path=…` for a note (or the vault itself when `relativePath` is nil).
  static func openURL(vaultRoot: URL, relativePath: String? = nil) -> URL? {
    let target = relativePath.map { vaultRoot.appendingPathComponent($0) } ?? vaultRoot
    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = "open"
    components.queryItems = [URLQueryItem(name: "path", value: target.path)]
    return components.url
  }

  /// Opens the note in Obsidian, launching it if needed. Returns false when Obsidian isn't installed.
  @discardableResult
  static func open(vaultRoot: URL, relativePath: String? = nil) -> Bool {
    guard isInstalled, let url = openURL(vaultRoot: vaultRoot, relativePath: relativePath) else { return false }
    return NSWorkspace.shared.open(url)
  }
}
