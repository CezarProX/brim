import AppKit

/// Observe only app identity and system events; never infer AI token usage from a running app.
@MainActor
final class WorkspaceActivityModel: ObservableObject {
  static let shared = WorkspaceActivityModel()
  @Published private(set) var appName = ""
  @Published private(set) var appIcon: NSImage?
  @Published private(set) var appURL: URL?
  @Published private(set) var systemTitle = ""
  @Published private(set) var systemSymbol = "capslock.fill"
  @Published private(set) var systemValue: Double?
  @Published private(set) var systemUntil = Date.distantPast
  private var observer: NSObjectProtocol?
  private var timer: Timer?
  private var started = false
  private var lastCaps: Bool?
  var workspaceEnabled: Bool { AppSettings.shared.workspaceActivityEnabled }
  var systemEnabled: Bool { AppSettings.shared.systemActivityEnabled }

  func setWorkspaceEnabled(_ enabled: Bool) {
    objectWillChange.send()
    AppSettings.shared.workspaceActivityEnabled = enabled
    if enabled { updateApp() }
    if started { configureObservation() }
  }

  func setSystemEnabled(_ enabled: Bool) {
    objectWillChange.send()
    AppSettings.shared.systemActivityEnabled = enabled
    lastCaps = nil
    if !enabled { systemUntil = .distantPast }
    if started { configureObservation() }
  }

  func start() {
    guard !started else { return }
    started = true
    updateApp()
    configureObservation()
  }

  private func configureObservation() {
    if workspaceEnabled, observer == nil {
      observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.updateApp() } }
    } else if !workspaceEnabled, let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      self.observer = nil
    }
    if !systemEnabled {
      timer?.invalidate()
      timer = nil
    }
    guard systemEnabled, timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, AppSettings.shared.systemActivityEnabled else { return }
        self.capsChanged(NSEvent.modifierFlags.contains(.capsLock))
      }
    }
  }

  func stop() {
    started = false
    if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observer = nil
    timer?.invalidate()
    timer = nil
  }

  private func updateApp() {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier
    else { return }
    appName = app.localizedName ?? "Application"
    appIcon = app.icon
    appURL = app.bundleURL
  }

  private func capsChanged(_ enabled: Bool) {
    defer { lastCaps = enabled }
    guard AppSettings.shared.systemActivityEnabled, let lastCaps, lastCaps != enabled else {
      return
    }
    systemTitle = enabled ? "Caps Lock on" : "Caps Lock off"
    systemSymbol = "capslock.fill"
    systemValue = nil
    systemUntil = .now.addingTimeInterval(2)
    IslandFlashCenter.shared.show(
      enabled ? "On" : "Off", symbol: enabled ? "capslock.fill" : "capslock",
      tint: enabled ? .green : .white)
  }
}
