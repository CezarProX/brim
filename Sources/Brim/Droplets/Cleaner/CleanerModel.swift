import AppKit
import SwiftUI

struct CleanerItem: Identifiable, Hashable {
  let leftover: Leftover
  var size: Int64
  var id: String { leftover.id }
}

/// State for the Cleaner: the app list, the chosen app's leftovers, the cache view.
///
/// Safety rules, all enforced here and in `CleanerSafety`:
/// - nothing is ticked until you tick it (or press "Select suggested", which only ticks files named
///   after the app's bundle identifier),
/// - nothing moves until a second, explicit confirmation that states the count and size,
/// - everything goes to the Trash; nothing is deleted outright.
@MainActor
final class CleanerModel: ObservableObject {
  enum Mode: String, CaseIterable, Identifiable {
    case uninstall = "Uninstall", caches = "Caches"
    var id: String { rawValue }
    var title: String { self == .uninstall ? L10n.tr("Apps") : L10n.tr("Caches") }
  }

  @Published var mode: Mode = .uninstall
  @Published var search = ""
  @Published private(set) var apps: [InstalledApp] = []
  @Published private(set) var appsLoaded = false
  @Published private(set) var chosen: InstalledApp?
  @Published private(set) var items: [CleanerItem] = []
  @Published private(set) var appSize: Int64 = 0
  @Published private(set) var cacheItems: [CleanerItem] = []
  @Published private(set) var cachesLoaded = false
  @Published private(set) var selected: Set<String> = []
  @Published private(set) var includeApp = false
  @Published private(set) var isScanning = false
  @Published private(set) var confirming = false
  @Published private(set) var message: String?

  let home: URL
  private let trasher: (URL) throws -> Void
  private var scanTask: Task<Void, Never>?

  init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser, apps: [InstalledApp]? = nil,
    trasher: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
  ) {
    self.home = home
    self.trasher = trasher
    if let apps {
      self.apps = apps
      appsLoaded = true
    } else {
      Task { await self.loadApps() }
    }
  }

  var filteredApps: [InstalledApp] {
    let removable = apps.filter { CleanerSafety.isRemovableApp($0.url, bundleID: $0.bundleID, home: home) }
    let query = search.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return removable }
    return removable.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }

  var isRunning: Bool {
    guard let id = chosen?.bundleID else { return false }
    return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
  }

  private var currentItems: [CleanerItem] { mode == .uninstall ? items : cacheItems }
  private var appCounts: Bool { mode == .uninstall && includeApp && chosen != nil }

  var selectedBytes: Int64 {
    currentItems.filter { selected.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size } + (appCounts ? appSize : 0)
  }

  var selectionCount: Int { selected.count + (appCounts ? 1 : 0) }

  /// Items whose name carries the app's bundle identifier: the ones "Select suggested" ticks.
  var suggestedIDs: Set<String> {
    Set(currentItems.filter { $0.leftover.confidence == .bundleID }.map(\.id))
  }

  /// True when the app is open and the app itself is ticked: it cannot be trashed while running.
  var blockedByRunningApp: Bool { appCounts && isRunning }

  var canMove: Bool { selectionCount > 0 && !blockedByRunningApp && !isScanning }

  /// Opens on the right list: the app list loads itself; the cache list loads when first shown.
  func refreshIfNeeded() {
    if mode == .caches, !cachesLoaded, !isScanning { loadCaches() }
  }

  func loadApps() async {
    apps = await InstalledApps.shared.all()
    appsLoaded = true
  }

  func choose(_ app: InstalledApp) {
    chosen = app
    items = []
    selected = []
    confirming = false
    message = nil
    includeApp = false
    scanTask?.cancel()
    isScanning = true
    let home = self.home
    scanTask = Task {
      let (found, appBytes) = await Task.detached(priority: .userInitiated) {
        let leftovers = CleanerMatcher.find(appName: app.name, bundleID: app.bundleID, home: home)
        let sized = leftovers.map { CleanerItem(leftover: $0, size: CleanerScanner.size(of: $0.url)) }
        return (sized, CleanerScanner.size(of: app.url))
      }.value
      guard !Task.isCancelled else { return }
      items = found.sorted { $0.size > $1.size }
      appSize = appBytes
      isScanning = false
    }
  }

  /// Back to the app list.
  func leaveApp() {
    scanTask?.cancel()
    chosen = nil
    items = []
    selected = []
    includeApp = false
    confirming = false
    isScanning = false
  }

  func switchMode(_ new: Mode) {
    guard new != mode else { return }
    mode = new
    selected = []
    confirming = false
    message = nil
    if new == .caches, !cachesLoaded { loadCaches() }
  }

  func loadCaches() {
    isScanning = true
    selected = []
    confirming = false
    let home = self.home
    Task {
      let sized = await Task.detached(priority: .userInitiated) {
        CleanerMatcher.cacheFolders(home: home).map {
          CleanerItem(leftover: Leftover(url: $0, category: "Caches", confidence: .bundleID), size: CleanerScanner.size(of: $0))
        }
      }.value
      cacheItems = sized.sorted { $0.size > $1.size }
      cachesLoaded = true
      isScanning = false
    }
  }

  func toggle(_ item: CleanerItem) {
    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    confirming = false
  }

  func toggleApp() {
    includeApp.toggle()
    confirming = false
  }

  func selectSuggested() {
    selected = suggestedIDs
    confirming = false
  }

  func selectAll() {
    selected = Set(currentItems.map(\.id))
    confirming = false
  }

  func clearSelection() {
    selected = []
    includeApp = false
    confirming = false
  }

  func reveal(_ item: CleanerItem) {
    NSWorkspace.shared.activateFileViewerSelecting([item.leftover.url])
  }

  // MARK: Moving to the Trash (two steps)

  /// Step one: ask for confirmation. Nothing moves.
  func requestMove() {
    guard canMove else { return }
    message = nil
    confirming = true
  }

  func cancelMove() { confirming = false }

  /// Step two: only does anything after `requestMove()`. Moves the ticked items (and the app, if
  /// ticked) to the Trash.
  func confirmMove() {
    guard confirming, canMove else { return }
    confirming = false
    let list = currentItems
    var urls = list.filter { selected.contains($0.id) }.map(\.leftover.url)
    var sizes = Dictionary(list.map { ($0.leftover.url, $0.size) }, uniquingKeysWith: { first, _ in first })
    if appCounts, let app = chosen {
      urls.insert(app.url, at: 0)
      sizes[app.url] = appSize
    }
    let home = self.home
    let bundleID = chosen?.bundleID
    let appURL = chosen?.url
    let outcome = CleanerScanner.trash(urls, sizes: sizes, trasher: trasher) { url in
      if url == appURL { return CleanerSafety.isRemovableApp(url, bundleID: bundleID, home: home) }
      return CleanerSafety.isSafeLeftover(url, home: home)
    }
    let ok = outcome.moved.count
    let freed = CleanerScanner.format(outcome.freed)
    if outcome.failed.isEmpty {
      message = L10n.tr("Moved %lld to the Trash (%@).", ok, freed)
    } else {
      message = L10n.tr("Moved %lld; %lld could not be moved: %@", ok, outcome.failed.count, outcome.failed[0].1)
    }
    let movedPaths = Set(outcome.moved.map(\.path))
    items.removeAll { movedPaths.contains($0.leftover.url.path) }
    cacheItems.removeAll { movedPaths.contains($0.leftover.url.path) }
    selected.subtract(movedPaths)
    if let appURL, movedPaths.contains(appURL.path) {
      apps.removeAll { $0.url == appURL }
      leaveApp()
    } else {
      includeApp = false
    }
  }
}
