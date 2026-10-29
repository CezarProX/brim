import AppKit
import SwiftUI

/// Owns the launcher's global shortcut and its floating panel. The panel takes key focus so you
/// can type, closes when you click away, and puts you back in the app you came from.
@MainActor
final class ThunderstormController: NSObject, NSWindowDelegate {
  static let shared = ThunderstormController()
  private var panel: ThunderPanel?
  private var model: ThunderstormModel?
  private var target: NSRunningApplication?
  private var heightObserver: Any?
  private let hotkey = DropletHotkey()
  private let settings = AppSettings.shared

  /// Registers the shortcut when the launcher is enabled; call again after settings change.
  func start() {
    hotkey.unregister()
    guard settings.thunderstormEnabled else { close(); return }
    hotkey.onPress = { [weak self] in self?.toggle() }
    let shortcut = settings.thunderstormShortcut
    if shortcut.isSet, !hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
      IslandFlashCenter.shared.show("Launcher shortcut is taken", symbol: "bolt.fill", tint: .orange)
    }
  }

  func toggle() {
    if panel != nil { close() } else { show() }
  }

  func show() {
    close()
    target = NSWorkspace.shared.frontmostApplication.flatMap {
      $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0
    }
    let model = ThunderstormModel()
    model.onDismiss = { [weak self] in self?.close() }
    model.onPaste = { [weak self] text in self?.paste(text) }
    let host = NSHostingView(rootView: ThunderstormView(model: model))
    host.sizingOptions = []
    let size = CGSize(width: ThunderstormView.width, height: model.panelHeight)
    let panel = ThunderPanel(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentView = host
    self.model = model
    self.panel = panel
    place(panel, height: size.height)
    panel.makeKeyAndOrderFront(nil)
    heightObserver = model.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.resizeToFit() }
    }
  }

  func close() {
    guard let panel else { return }
    self.panel = nil
    self.model = nil
    heightObserver = nil
    panel.delegate = nil
    panel.orderOut(nil)
  }

  func windowDidResignKey(_ notification: Notification) { close() }

  private func resizeToFit() {
    guard let panel, let model else { return }
    place(panel, height: model.panelHeight, animate: true)
  }

  /// Top edge stays put (about a quarter of the way down the screen), the panel grows downward.
  private func place(_ panel: NSPanel, height: CGFloat, animate: Bool = false) {
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let top = bounds.maxY - bounds.height * 0.2
    let frame = CGRect(x: bounds.midX - ThunderstormView.width / 2, y: top - height, width: ThunderstormView.width, height: height)
    panel.setFrame(frame, display: true, animate: animate)
  }

  private func paste(_ text: String) { Self.paste(text, into: target) }

  /// Pastes `text` into `target` (clipboard restored afterwards); copy-only without Accessibility.
  static func paste(_ text: String, into target: NSRunningApplication?) {
    let pasteboard = NSPasteboard.general
    let saved = EmojiPasteboard.snapshot(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    guard AXIsProcessTrusted() else {
      IslandFlashCenter.shared.show("Copied snippet", symbol: "doc.on.clipboard", tint: .orange, detail: "Allow Accessibility to paste automatically")
      return
    }
    target?.activate()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      for down in [true, false] {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 9, keyDown: down)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
      }
      try? await Task.sleep(for: .milliseconds(450))
      EmojiPasteboard.restore(saved, to: pasteboard)
    }
  }
}

private final class ThunderPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
