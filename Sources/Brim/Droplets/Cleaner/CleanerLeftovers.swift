import Foundation

/// How sure we are that a file belongs to the app.
enum LeftoverConfidence: Sendable {
  /// Named after the bundle identifier: selected by default.
  case bundleID
  /// Only matches the app's display name: shown, but not selected until you tick it.
  case name
}

struct Leftover: Identifiable, Hashable, Sendable {
  let url: URL
  /// Library folder it was found in, e.g. "Caches".
  let category: String
  let confidence: LeftoverConfidence
  var id: String { url.path }
}

/// What may be touched. Every path Cleaner moves to the Trash is checked here first.
enum CleanerSafety {
  static let leftoverFolders = [
    "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers", "Logs",
    "Saved Application State", "HTTPStorages", "WebKit", "LaunchAgents", "Cookies",
  ]

  static func library(of home: URL) -> URL {
    home.resolvingSymlinksInPath().appendingPathComponent("Library", isDirectory: true)
  }

  /// True only for a real path strictly inside `<home>/Library/<folder>/<item>` (at least two
  /// components below Library, symlinks resolved, no `..`). Anything else — other users,
  /// /System, /Library, the Library folder itself, a symlink pointing out — is refused.
  static func isSafeLeftover(_ url: URL, home: URL) -> Bool {
    guard url.isFileURL, !url.pathComponents.contains("..") else { return false }
    let library = library(of: home).pathComponents
    let resolved = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    guard resolved.count >= library.count + 2, Array(resolved.prefix(library.count)) == library else { return false }
    return true
  }

  /// Apps that may be uninstalled: a real `.app` in /Applications or ~/Applications that is not
  /// Apple's, not Brim, and not inside the system volume.
  static func isRemovableApp(_ url: URL, bundleID: String?, home: URL, ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
    guard url.pathExtension == "app" else { return false }
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let roots = ["/Applications/", home.resolvingSymlinksInPath().path + "/Applications/"]
    guard roots.contains(where: { path.hasPrefix($0) }), !path.hasPrefix("/System/") else { return false }
    if let bundleID {
      if bundleID.hasPrefix("com.apple.") { return false }
      if bundleID == ownBundleID { return false }
    }
    return true
  }
}

enum CleanerMatcher {
  /// Whether a file name in a Library folder belongs to `bundleID` (identifier boundary aware:
  /// `com.foo.bar` matches `com.foo.bar.plist` and `com.foo.bar.helper` but not `com.foo.barista`).
  static func matchesBundleID(_ fileName: String, bundleID: String) -> Bool {
    let name = fileName.lowercased()
    let id = bundleID.lowercased()
    guard !id.isEmpty else { return false }
    if name == id { return true }
    for suffix in [".", "-"] where name.hasPrefix(id + suffix) { return true }
    // group.<id>, <TEAMID>.<id>, <TEAMID>.group.<id>
    if name == "group." + id || name.hasSuffix("." + id) || name.hasSuffix(".group." + id) { return true }
    return false
  }

  static func matchesName(_ fileName: String, appName: String) -> Bool {
    let stem = (fileName as NSString).deletingPathExtension.lowercased()
    let name = appName.lowercased()
    return name.count >= 4 && (stem == name || fileName.lowercased() == name)
  }

  /// Finds leftovers under `<home>/Library`. Pure over the file system passed in; never follows
  /// anything outside Library and drops anything `CleanerSafety` refuses.
  static func find(
    appName: String, bundleID: String?, home: URL, fileManager: FileManager = .default
  ) -> [Leftover] {
    let library = CleanerSafety.library(of: home)
    var found: [Leftover] = []
    for folder in CleanerSafety.leftoverFolders {
      let directory = library.appendingPathComponent(folder, isDirectory: true)
      let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
      for name in names where !name.hasPrefix(".") {
        let confidence: LeftoverConfidence?
        if let bundleID, matchesBundleID(name, bundleID: bundleID) {
          confidence = .bundleID
        } else if matchesName(name, appName: appName), folder != "Preferences", folder != "Preferences/ByHost" {
          confidence = .name
        } else {
          confidence = nil
        }
        guard let confidence else { continue }
        let url = directory.appendingPathComponent(name)
        guard CleanerSafety.isSafeLeftover(url, home: home) else { continue }
        found.append(Leftover(url: url, category: folder, confidence: confidence))
      }
    }
    return found
  }

  /// Top-level folders of `~/Library/Caches` that are safe to clear (not Apple's, not ours).
  static func cacheFolders(home: URL, fileManager: FileManager = .default, ownBundleID: String? = Bundle.main.bundleIdentifier) -> [URL] {
    let directory = CleanerSafety.library(of: home).appendingPathComponent("Caches", isDirectory: true)
    let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    return names
      .filter { !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("com.apple.") && $0 != ownBundleID }
      .map { directory.appendingPathComponent($0) }
      .filter { CleanerSafety.isSafeLeftover($0, home: home) }
      .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
  }
}
