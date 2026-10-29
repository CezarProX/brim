import AppKit
import Foundation

/// Installed applications for the launcher and for Cleaner. Scanning is cheap (two directory
/// levels) and runs off the main thread; the list is cached until `refresh()`.
struct InstalledApp: Identifiable, Hashable, Sendable {
  let name: String
  let url: URL
  let bundleID: String?
  var id: String { url.path }
}

actor InstalledApps {
  static let shared = InstalledApps()
  private var cache: [InstalledApp]?

  static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
    [
      URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
      URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities"),
      home.appendingPathComponent("Applications"),
    ]
  }

  func all(forceRefresh: Bool = false) -> [InstalledApp] {
    if let cache, !forceRefresh { return cache }
    let found = Self.scan(roots: Self.roots())
    cache = found
    return found
  }

  /// Lists `.app` bundles in each root and one level of subfolders (e.g. /Applications/Adobe/...).
  static func scan(roots: [URL], fileManager: FileManager = .default) -> [InstalledApp] {
    var seen = Set<String>()
    var result: [InstalledApp] = []
    func add(_ url: URL) {
      guard url.pathExtension == "app", seen.insert(url.path).inserted else { return }
      let bundleID = Bundle(url: url)?.bundleIdentifier
      result.append(InstalledApp(name: url.deletingPathExtension().lastPathComponent, url: url, bundleID: bundleID))
    }
    for root in roots {
      let children = (try? fileManager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
      for child in children {
        if child.pathExtension == "app" { add(child); continue }
        let isFolder = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isFolder else { continue }
        let nested = (try? fileManager.contentsOfDirectory(
          at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        nested.forEach(add)
      }
    }
    return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

/// File search through Spotlight's index. One query at a time; results arrive on the main actor.
@MainActor
final class ThunderFileSearch {
  private var query: NSMetadataQuery?
  private var observer: NSObjectProtocol?
  var onResults: ([URL]) -> Void = { _ in }

  func search(_ text: String) {
    stop()
    let term = text.trimmingCharacters(in: .whitespaces)
    guard term.count >= 2 else { onResults([]); return }
    let query = NSMetadataQuery()
    query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, term)
    query.searchScopes = [NSMetadataQueryUserHomeScope]
    query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
    observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.finish() }
    }
    self.query = query
    query.start()
  }

  func stop() {
    query?.stop()
    query = nil
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }

  private func finish() {
    guard let query else { return }
    query.disableUpdates()
    var urls: [URL] = []
    for index in 0..<min(query.resultCount, 200) {
      guard let item = query.result(at: index) as? NSMetadataItem,
        let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
      else { continue }
      if Self.isUserVisible(path) { urls.append(URL(fileURLWithPath: path)) }
      if urls.count >= 8 { break }
    }
    onResults(urls)
  }

  /// Hides Library internals, dot-files and app bundle contents from file results.
  nonisolated static func isUserVisible(_ path: String) -> Bool {
    let parts = path.split(separator: "/")
    if parts.contains(where: { $0.hasPrefix(".") }) { return false }
    let noise = ["/Library/", ".app/", "/node_modules/", "/site-packages/", "/venv/", "/.build/", "/DerivedData/", "/go/pkg/", "/Pods/"]
    if noise.contains(where: path.contains) { return false }
    return true
  }
}

enum ThunderSystemRunner {
  /// Runs a system command; returns an error text to show, or nil on success.
  @MainActor
  static func run(_ command: ThunderSystemCommand) -> String? {
    switch command {
    case .sleepDisplay: return runProcess("/usr/bin/pmset", ["displaysleepnow"])
    case .lockScreen: return lockScreen()
    case .emptyTrash: return script("tell application \"Finder\" to empty the trash")
    case .toggleDarkMode:
      return script(
        "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }
  }

  private static func runProcess(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    do {
      try process.run()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private static func script(_ source: String) -> String? {
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    return (error?[NSAppleScript.errorMessage] as? String)
  }

  /// `SACLockScreenImmediate` from the login framework, loaded at runtime; falls back to ⌃⌘Q.
  private static func lockScreen() -> String? {
    if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
      let symbol = dlsym(handle, "SACLockScreenImmediate")
    {
      typealias LockFunction = @convention(c) () -> Int32
      _ = unsafeBitCast(symbol, to: LockFunction.self)()
      return nil
    }
    guard AXIsProcessTrusted() else { return "Allow Accessibility to lock the screen" }
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: down)  // Q
      event?.flags = [.maskCommand, .maskControl]
      event?.post(tap: .cghidEventTap)
    }
    return nil
  }
}
