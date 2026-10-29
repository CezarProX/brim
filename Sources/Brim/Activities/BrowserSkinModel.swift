import AppKit
import Carbon

/// Browsers the skin understands, with their scripting dialect.
enum SkinBrowser: String, CaseIterable, Sendable {
  case safari = "com.apple.Safari"
  case chrome = "com.google.Chrome"
  case arc = "company.thebrowser.Browser"
  case brave = "com.brave.Browser"
  case edge = "com.microsoft.edgemac"

  var name: String {
    switch self {
    case .safari: "Safari"
    case .chrome: "Chrome"
    case .arc: "Arc"
    case .brave: "Brave"
    case .edge: "Edge"
    }
  }

  var isChromium: Bool { self != .safari }

  /// AppleScript that returns "title\turl\ttabCount\nother tab titles…" for the front window.
  var readScript: String {
    let app = "application id \"\(rawValue)\""
    if isChromium {
      return """
        tell \(app)
          if (count of windows) is 0 then return ""
          set w to front window
          set t to active tab of w
          set out to (title of t) & tab & (URL of t) & tab & (count of tabs of w)
          repeat with other in (tabs of w)
            if (id of other) is not (id of t) then set out to out & linefeed & (title of other) & tab & (URL of other)
          end repeat
          return out
        end tell
        """
    }
    return """
      tell \(app)
        if (count of windows) is 0 then return ""
        set w to front window
        set t to current tab of w
        set out to (name of t) & tab & (URL of t) & tab & (count of tabs of w)
        repeat with other in (tabs of w)
          if (index of other) is not (index of t) then set out to out & linefeed & (name of other) & tab & (URL of other)
        end repeat
        return out
      end tell
      """
  }

  func commandScript(_ command: BrowserCommand) -> String {
    let app = "application id \"\(rawValue)\""
    switch (command, isChromium) {
    case (.back, true): return "tell \(app) to go back active tab of front window"
    case (.forward, true): return "tell \(app) to go forward active tab of front window"
    case (.reload, true): return "tell \(app) to reload active tab of front window"
    case (.newTab, true): return "tell \(app) to make new tab at end of tabs of front window"
    // Safari has no history verbs; its own JavaScript bridge would need an extra opt-in.
    case (.back, false): return "tell \(app) to do JavaScript \"history.back()\" in current tab of front window"
    case (.forward, false): return "tell \(app) to do JavaScript \"history.forward()\" in current tab of front window"
    case (.reload, false):
      return "tell \(app) to set URL of current tab of front window to (URL of current tab of front window)"
    case (.newTab, false):
      return "tell \(app) to set current tab of front window to (make new tab at end of tabs of front window)"
    }
  }
}

enum BrowserCommand: Sendable { case back, forward, reload, newTab }

struct BrowserTab: Equatable, Identifiable, Sendable {
  let title: String
  let url: String
  var id: String { url + title }
  var host: String { URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url }
}

struct BrowserSnapshot: Equatable, Sendable {
  let browser: SkinBrowser
  let active: BrowserTab
  let tabCount: Int
  let others: [BrowserTab]

  /// Parses the tab-separated reply of `readScript`.
  static func parse(_ text: String, browser: SkinBrowser) -> BrowserSnapshot? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    guard let first = lines.first else { return nil }
    let fields = first.components(separatedBy: "\t")
    guard fields.count >= 3, let count = Int(fields[2].trimmingCharacters(in: .whitespaces)) else {
      return nil
    }
    let others = lines.dropFirst().prefix(8).compactMap { line -> BrowserTab? in
      let parts = line.components(separatedBy: "\t")
      guard parts.count >= 2 else { return nil }
      return BrowserTab(title: String(parts[0].prefix(200)), url: String(parts[1].prefix(2048)))
    }
    return BrowserSnapshot(
      browser: browser,
      active: BrowserTab(title: String(fields[0].prefix(200)), url: String(fields[1].prefix(2048))),
      tabCount: count, others: Array(others))
  }
}

/// When a supported browser is frontmost, the island shows its tab and navigation.
/// Reads only after macOS has granted Automation for that browser.
@MainActor
final class BrowserSkinModel: ObservableObject {
  static let shared = BrowserSkinModel()
  @Published private(set) var snapshot: BrowserSnapshot?
  @Published private(set) var frontBrowser: SkinBrowser?
  @Published private(set) var needsPermission = false
  @Published private(set) var message: String?
  private var observer: NSObjectProtocol?
  private var timer: Timer?
  private let queue = DispatchQueue(label: "Brim.BrowserSkin")
  private var reading = false

  var enabled: Bool { AppSettings.shared.browserSkinEnabled }

  func start() {
    guard observer == nil else { return }
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.frontChanged() } }
    frontChanged()
  }

  func stop() {
    if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observer = nil
    timer?.invalidate()
    timer = nil
    snapshot = nil
    frontBrowser = nil
  }

  private func frontChanged() {
    let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    let browser = enabled ? bundle.flatMap(SkinBrowser.init(rawValue:)) : nil
    // Keep the last browser while Brim itself is frontmost (the user is using the island).
    if bundle == Bundle.main.bundleIdentifier { return }
    frontBrowser = browser
    timer?.invalidate()
    timer = nil
    guard browser != nil else {
      snapshot = nil
      return
    }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    guard let browser = frontBrowser, !reading else { return }
    guard Self.permission(for: browser, ask: false) else {
      needsPermission = true
      snapshot = nil
      return
    }
    needsPermission = false
    reading = true
    let script = browser.readScript
    queue.async { [weak self] in
      let parsed = Self.run(script).text.flatMap { BrowserSnapshot.parse($0, browser: browser) }
      Task { @MainActor in
        self?.reading = false
        guard self?.frontBrowser == browser else { return }
        self?.snapshot = parsed
      }
    }
  }

  /// Asks macOS for Automation access to the front browser; the system shows its prompt once.
  func connect() {
    guard let browser = frontBrowser ?? snapshot?.browser else { return }
    queue.async {
      _ = Self.permission(for: browser, ask: true)
      Task { @MainActor [weak self] in self?.refresh() }
    }
  }

  func perform(_ command: BrowserCommand) {
    guard let browser = snapshot?.browser else { return }
    let script = browser.commandScript(command)
    queue.async { [weak self] in
      let ok = Self.run(script).ok
      Task { @MainActor in
        if !ok && browser == .safari && (command == .back || command == .forward) {
          self?.message = "In Safari → Develop, allow JavaScript from Apple Events for back and forward."
        }
        self?.refresh()
      }
    }
  }

  /// Commands often return nothing on success, so success and text are reported separately.
  nonisolated private static func run(_ source: String) -> (ok: Bool, text: String?) {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return (false, nil) }
    let result = script.executeAndReturnError(&error)
    guard error == nil else { return (false, nil) }
    return (true, result.stringValue)
  }

  nonisolated static func permission(for browser: SkinBrowser, ask: Bool) -> Bool {
    guard
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.rawValue).first
    else { return false }
    let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
    return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) == noErr
  }
}
