// DropClipModel.swift
// Brim
//
// State for the floating action bar plus the controller that reads the selection on the shortcut.

import AppKit
import SwiftUI

@MainActor
final class DropClipModel: ObservableObject {
  static let shared = DropClipModel()
  @Published private(set) var snapshot: SelectionSnapshot?
  @Published private(set) var outcome: DropClipOutcome?
  @Published private(set) var runningAction: DropClipAction?
  /// Bumped to ask the translation host (macOS 15+) to translate `snapshot`.
  @Published private(set) var translationRequest = 0
  @Published var lastError: String?

  private let settings: AppSettings
  init(settings: AppSettings = .shared) { self.settings = settings }

  var text: String { snapshot?.text ?? "" }

  /// Actions for the frontmost app: global list + custom actions, minus this app's hidden ones.
  var actions: [DropClipAction] {
    let all = settings.dropClipActions + settings.dropClipCustomActions.map(\.action)
    return settings.dropClipRules.actions(global: all, in: snapshot?.bundleID)
  }

  func title(of action: DropClipAction) -> String {
    if case .custom(let id) = action { return settings.dropClipCustomActions.first { $0.id == id }?.title ?? "Custom action" }
    return action.title
  }

  func begin(_ snapshot: SelectionSnapshot) {
    self.snapshot = snapshot
    outcome = nil
    runningAction = nil
  }

  func clear() {
    snapshot = nil
    outcome = nil
    runningAction = nil
  }

  func perform(_ action: DropClipAction) async {
    guard !text.isEmpty else { return }
    if action == .translate {
      runningAction = .translate
      if #available(macOS 15.0, *) { translationRequest += 1 } else { openWebTranslation() }
      return
    }
    runningAction = action
    let result = await DropClipRunner.run(action, text: text, settings: settings)
    runningAction = nil
    if let result { outcome = result }
  }

  func setTranslation(_ translated: String?, error: String?) {
    runningAction = nil
    if let translated {
      DropClipRunner.copy(translated)
      outcome = DropClipOutcome(title: "Translation · copied", body: translated, copyable: translated, symbol: "translate")
    } else {
      outcome = DropClipOutcome(title: "Couldn’t translate", body: error, copyable: nil, symbol: "exclamationmark.triangle", isError: true)
    }
  }

  var translationTarget: Locale.Language {
    let code = settings.dropClipTranslateTarget
    return code == "system" ? (Locale.current.language) : Locale.Language(identifier: code)
  }

  /// macOS 14 has no Translation framework: open the translator in the browser (the user's explicit click).
  private func openWebTranslation() {
    let target = Locale.current.language.languageCode?.identifier ?? "en"
    let template = "https://translate.google.com/?sl=auto&tl=\(target)&op=translate&text={text}"
    runningAction = nil
    if let url = DropClipTransforms.expand(template: template, text: text) { NSWorkspace.shared.open(url) }
  }
}

private final class DropClipPanel: NSPanel {
  override var canBecomeKey: Bool { false }
}

@MainActor
final class DropClipController {
  static let shared = DropClipController()
  private var panel: NSPanel?
  private var hosting: NSHostingView<AnyView>?
  private var monitors: [Any] = []
  private var dismissTimer: Timer?
  private var resizeObserver: Any?
  private let settings = AppSettings.shared
  private let model = DropClipModel.shared
  private init() {}

  func start() {
    stop()
    guard settings.dropClipEnabled else { return }
    if !SelectionReader.isTrusted { SelectionReader.requestTrust() }
    DropletHotkeyCenter.shared.register(.dropClip, shortcut: settings.dropClipShortcut) { [weak self] in
      Task { await self?.trigger() }
    }
  }

  func stop() {
    DropletHotkeyCenter.shared.unregister(.dropClip)
    dismiss()
  }

  func settingsChanged() { settings.dropClipEnabled ? start() : stop() }

  func trigger() async {
    if panel?.isVisible == true { return dismiss() }
    guard SelectionReader.isTrusted else {
      SelectionReader.requestTrust()
      IslandFlashCenter.shared.show("Allow Accessibility for DropClip", symbol: "hand.raised", tint: .orange)
      return
    }
    // Let the shortcut's modifier keys come up before any synthetic ⌘C.
    try? await Task.sleep(for: .milliseconds(120))
    guard let snapshot = await SelectionReader.read(allowCopyFallback: settings.dropClipCopyFallback) else {
      IslandFlashCenter.shared.show("No text selected", symbol: "text.cursor", tint: .white)
      return
    }
    guard settings.dropClipRules.isEnabled(in: snapshot.bundleID) else { return }
    model.begin(snapshot)
    present(near: snapshot.bounds)
  }

  // MARK: Panel

  private func present(near bounds: CGRect?) {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    hosting?.rootView = AnyView(DropClipBarView(model: model, onClose: { [weak self] in self?.dismiss() }))
    resize(panel, anchoredAt: nil)
    panel.setFrameOrigin(origin(for: panel.frame.size, near: bounds))
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
      panel.animator().alphaValue = 1
    }
    installMonitors(for: panel)
    scheduleDismiss()
    resizeObserver = model.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.refit(); self?.scheduleDismiss() }
    }
  }

  private func refit() {
    guard let panel, panel.isVisible else { return }
    resize(panel, anchoredAt: CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
  }

  private func resize(_ panel: NSPanel, anchoredAt topLeft: CGPoint?) {
    guard let hosting else { return }
    let size = hosting.fittingSize
    var frame = panel.frame
    frame.size = size
    if let topLeft { frame.origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height) }
    panel.setFrame(frame, display: true)
  }

  /// Above the selection when there is room, otherwise below; near the pointer without bounds.
  private func origin(for size: CGSize, near bounds: CGRect?) -> CGPoint {
    let anchor = bounds ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 18))
    let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    var x = anchor.midX - size.width / 2
    var y = anchor.maxY + 8
    if y + size.height > visible.maxY { y = anchor.minY - size.height - 8 }
    x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
    y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
    return CGPoint(x: x, y: y)
  }

  private func makePanel() -> NSPanel {
    let panel = DropClipPanel(
      contentRect: CGRect(x: 0, y: 0, width: 380, height: 52),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    panel.contentView = host
    hosting = host
    return panel
  }

  private func installMonitors(for panel: NSPanel) {
    removeMonitors()
    let click: (NSEvent) -> Void = { [weak self, weak panel] _ in
      guard let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
      Task { @MainActor in self?.dismiss() }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel], handler: click) { monitors.append(global) }
    if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
      if event.keyCode == 53 { Task { @MainActor in self?.dismiss() } }
    }) { monitors.append(keys) }
  }

  private func removeMonitors() {
    monitors.forEach { NSEvent.removeMonitor($0) }
    monitors = []
    resizeObserver = nil
  }

  private func scheduleDismiss() {
    dismissTimer?.invalidate()
    dismissTimer = Timer.scheduledTimer(withTimeInterval: 14, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss() }
    }
  }

  func dismiss() {
    dismissTimer?.invalidate()
    removeMonitors()
    guard let panel, panel.isVisible else { return model.clear() }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.12
      panel.animator().alphaValue = 0
    }, completionHandler: { panel.orderOut(nil) })
    model.clear()
  }
}
