import AppKit

/// What the Front App widget knows about the app in front: identity, windows, and the recent apps
/// to switch to. Observes the workspace only while the widget is on screen.
@MainActor
final class FrontAppModel: ObservableObject {
  struct Entry: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
  }

  static let shared = FrontAppModel()

  @Published private(set) var front: NSRunningApplication?
  @Published private(set) var windowCount = 0
  @Published private(set) var recents: [Entry] = []
  /// The app a Force Quit is waiting to be confirmed for.
  @Published private(set) var forceQuitArmed: pid_t?

  private var mru: [pid_t] = []
  private var observers: [NSObjectProtocol] = []
  private var viewers = 0
  private var disarm: Task<Void, Never>?
  private let ownPID = ProcessInfo.processInfo.processIdentifier

  // MARK: Pure helpers (tested)

  /// Moves `pid` to the front of the most-recently-used list, dropping duplicates.
  nonisolated static func promote(_ pid: pid_t, in list: [pid_t]) -> [pid_t] {
    [pid] + list.filter { $0 != pid }
  }

  /// Apps that cannot be quit by the user from here (the Finder relaunches itself; the Dock is the shell).
  nonisolated static func isProtected(bundleID: String?) -> Bool {
    guard let bundleID else { return false }
    return ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.WindowServer"].contains(bundleID)
  }

  nonisolated static func openDuration(since launch: Date?, now: Date = .now) -> String? {
    guard let launch else { return nil }
    let minutes = Int(now.timeIntervalSince(launch) / 60)
    if minutes < 1 { return L10n.tr("Just opened") }
    if minutes < 60 { return L10n.tr("Open for %lld min", minutes) }
    if minutes < 24 * 60 { return L10n.tr("Open for %lld h", minutes / 60) }
    return L10n.tr("Open for %lld d", minutes / (24 * 60))
  }

  // MARK: Lifecycle

  func attach() {
    viewers += 1
    guard observers.isEmpty else { return }
    let center = NSWorkspace.shared.notificationCenter
    let names: [NSNotification.Name] = [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didUnhideApplicationNotification,
    ]
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let pid = app?.processIdentifier
        let activated = name == NSWorkspace.didActivateApplicationNotification
        Task { @MainActor in self?.workspaceChanged(activated: activated ? pid : nil) }
      }
    }
    if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ownPID {
      mru = Self.promote(frontmost.processIdentifier, in: mru)
    }
    refresh()
  }

  func detach() {
    viewers = max(0, viewers - 1)
    guard viewers == 0 else { return }
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  private func workspaceChanged(activated: pid_t?) {
    if let activated, activated != ownPID { mru = Self.promote(activated, in: mru) }
    refresh()
  }

  func refresh() {
    let running = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
    }
    let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    mru = mru.filter { byPID[$0] != nil }
    // Apps never activated since we started: newest launches first.
    let rest = running.filter { !mru.contains($0.processIdentifier) }
      .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
    let ordered = mru.compactMap { byPID[$0] } + rest
    front = ordered.first
    recents = ordered.prefix(11).map { Entry(id: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon) }
    windowCount = front.map { Self.windowCount(pid: $0.processIdentifier) } ?? 0
    if forceQuitArmed != front?.processIdentifier { forceQuitArmed = nil }
  }

  /// Ordinary on-screen windows of a process; titles would need Screen Recording, a count does not.
  nonisolated static func windowCount(pid: pid_t) -> Int {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]]
    else { return 0 }
    return list.filter { info in
      guard (info[kCGWindowOwnerPID as String] as? Int32) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
        let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
      else { return false }
      return (bounds["Width"] ?? 0) > 60 && (bounds["Height"] ?? 0) > 40
    }.count
  }

  // MARK: Actions

  var canQuitFront: Bool { front.map { !Self.isProtected(bundleID: $0.bundleIdentifier) } ?? false }

  func hideFront() {
    front?.hide()
    refreshSoon()
  }

  func hideOthers() {
    let keep = front?.processIdentifier
    for app in NSWorkspace.shared.runningApplications
    where app.activationPolicy == .regular && app.processIdentifier != keep && app.processIdentifier != ownPID
      && !Self.isProtected(bundleID: app.bundleIdentifier) {
      app.hide()
    }
    refreshSoon()
  }

  func quitFront() {
    guard canQuitFront else { return }
    front?.terminate()
    refreshSoon()
  }

  /// First tap arms (the button asks "Sure?"); a second tap within four seconds force-quits.
  func forceQuitFront() {
    guard canQuitFront, let front else { return }
    if forceQuitArmed == front.processIdentifier {
      front.forceTerminate()
      forceQuitArmed = nil
      refreshSoon()
      return
    }
    forceQuitArmed = front.processIdentifier
    disarm?.cancel()
    disarm = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled else { return }
      self?.forceQuitArmed = nil
    }
  }

  func revealFront() {
    if let url = front?.bundleURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
  }

  func activate(_ entry: Entry) {
    NSRunningApplication(processIdentifier: entry.id)?.activate()
  }

  private func refreshSoon() {
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(450))
      self?.refresh()
    }
  }
}
