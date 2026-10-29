// TermiNotchModel.swift
// Brim
//
// Tabs, the external-terminal hand-off, and the Quake-style drop-down panel.

import AppKit
import SwiftUI

enum ExternalTerminal: String, CaseIterable, Identifiable {
  case terminal, iterm, warp
  var id: String { rawValue }
  var title: String {
    switch self {
    case .terminal: "Terminal"
    case .iterm: "iTerm"
    case .warp: "Warp"
    }
  }
  var bundleID: String {
    switch self {
    case .terminal: "com.apple.Terminal"
    case .iterm: "com.googlecode.iterm2"
    case .warp: "dev.warp.Warp-Stable"
    }
  }
  var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}

@MainActor
final class TermiNotchModel: ObservableObject {
  static let shared = TermiNotchModel()
  @Published private(set) var tabs: [TerminalSession] = []
  @Published var selectedID: UUID?
  @Published var showsHistory = false
  private let settings: AppSettings

  init(settings: AppSettings = .shared) { self.settings = settings }

  var selected: TerminalSession? { tabs.first { $0.id == selectedID } ?? tabs.first }
  var fontSize: CGFloat { CGFloat(settings.termiNotchFontSize) }

  /// Opens the first tab on demand: no shell exists until the terminal is shown.
  func ensureTab() {
    if tabs.isEmpty { newTab() } else { selected?.start() }
  }

  /// Adds an already-prepared session as a tab.
  func adopt(_ session: TerminalSession) {
    tabs.append(session)
    selectedID = session.id
  }

  func newTab() {
    let directory = settings.termiNotchInheritFolder ? (selected?.currentDirectory ?? NSHomeDirectory()) : NSHomeDirectory()
    let session = TerminalSession(directory: directory)
    tabs.append(session)
    selectedID = session.id
    session.start()
  }

  func close(_ session: TerminalSession) {
    session.stop()
    guard let index = tabs.firstIndex(where: { $0.id == session.id }) else { return }
    tabs.remove(at: index)
    if selectedID == session.id { selectedID = tabs[safe: min(index, tabs.count - 1)]?.id }
    if tabs.isEmpty { selectedID = nil }
  }

  func closeAll() {
    tabs.forEach { $0.stop() }
    tabs = []
    selectedID = nil
  }

  /// Opens the chosen terminal app at the shell's current folder. Never runs a command.
  @discardableResult
  func handOff(to app: ExternalTerminal) -> Bool {
    let path = selected?.currentDirectory ?? NSHomeDirectory()
    guard let appURL = app.appURL else {
      IslandFlashCenter.shared.show("\(app.title) isn’t installed", symbol: "exclamationmark.triangle", tint: .orange)
      return false
    }
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([URL(fileURLWithPath: path, isDirectory: true)], withApplicationAt: appURL, configuration: configuration)
    return true
  }
}

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Quake-style drop-down

private final class TermiPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class TermiNotchController {
  static let shared = TermiNotchController()
  private var panel: NSPanel?
  private let settings = AppSettings.shared
  private init() {}

  func start() {
    stop()
    guard settings.termiNotchEnabled else { return }
    DropletHotkeyCenter.shared.register(.termiNotch, shortcut: settings.termiNotchShortcut) { [weak self] in self?.toggle() }
  }

  func stop() {
    DropletHotkeyCenter.shared.unregister(.termiNotch)
    panel?.orderOut(nil)
  }

  func settingsChanged() {
    if settings.termiNotchEnabled { start() } else {
      stop()
      TermiNotchModel.shared.closeAll()
    }
  }

  func toggle() {
    if let panel, panel.isVisible { return hide() }
    show()
  }

  private func hide() {
    guard let panel else { return }
    let target = panel.frame.offsetBy(dx: 0, dy: panel.frame.height)
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.18
      panel.animator().setFrame(target, display: true)
      panel.animator().alphaValue = 0
    }, completionHandler: { panel.orderOut(nil) })
  }

  private func show() {
    TermiNotchModel.shared.ensureTab()
    let panel = self.panel ?? makePanel()
    self.panel = panel
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    guard let frame = screen?.visibleFrame else { return }
    let size = CGSize(width: min(720, frame.width - 40), height: 320)
    let end = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 6, width: size.width, height: size.height)
    panel.setFrame(end.offsetBy(dx: 0, dy: size.height), display: false)
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(end, display: true)
      panel.animator().alphaValue = 1
    }
  }

  private func makePanel() -> NSPanel {
    let panel = TermiPanel(
      contentRect: CGRect(x: 0, y: 0, width: 720, height: 320),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    let root = TermiNotchIslandView(compact: false)
      .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous).strokeBorder(IslandFill.hairline) }
      .preferredColorScheme(.dark)
    panel.contentView = NSHostingView(rootView: root)
    return panel
  }
}
