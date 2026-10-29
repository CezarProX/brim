import AppKit
import SwiftUI

/// Shows the Command Center as a glass popover under the menu-bar icon.
@MainActor
final class CommandCenterController: NSObject {
  static let shared = CommandCenterController()

  let store = CommandCenterStore.shared
  let pager = CommandCenterPageState()
  private var panel: CommandCenterPanel?
  private var clickMonitor: Any?
  private var keyMonitor: Any?
  /// A click on the menu-bar icon closes the popover on mouse-down (outside click) and then fires the icon's
  /// action on mouse-up; without this guard that second event would reopen it straight away.
  private var closedByOutsideClickAt = Date.distantPast

  var isVisible: Bool { panel?.isVisible ?? false }

  func toggle(anchoredTo button: NSStatusBarButton?, editing: Bool = false) {
    if isVisible { close(); return }
    guard Date().timeIntervalSince(closedByOutsideClickAt) > 0.35 else { return }
    show(anchoredTo: button, editing: editing)
  }

  func show(anchoredTo button: NSStatusBarButton?, editing: Bool = false) {
    close()
    store.reload()
    store.isEditing = editing
    let settings = AppSettings.shared
    pager.page = CommandCenterLayout.startPage(settings.commandCenterStartPage, lastUsed: settings.commandCenterLastPage,
                                               pageCount: store.pageCount)
    let root = CommandCenterView(store: store, pager: pager, onAction: { [weak self] in self?.handle($0) },
                                 onClose: { [weak self] in self?.close() })
    let host = NSHostingView(rootView: root)
    let size = CommandCenterView.size
    host.frame = CGRect(origin: .zero, size: size)
    let panel = CommandCenterPanel(contentRect: CGRect(origin: .zero, size: size))
    panel.contentView = host
    panel.setFrame(frame(for: size, anchor: button), display: false)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    panel.makeKey()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      panel.animator().alphaValue = 1
    }
    self.panel = panel
    installMonitors()
  }

  func close() {
    removeMonitors()
    store.isEditing = false
    guard let closing = panel else { return }
    panel = nil
    // Fade out rather than vanish; a reopen in the meantime builds a fresh panel.
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.14
      closing.animator().alphaValue = 0
    }, completionHandler: { closing.orderOut(nil) })
  }

  /// Tiles run their action; actions that leave the app's windows (capture, settings) close the popover first.
  private func handle(_ kind: TileKind) {
    let closes = kind.closesAfterAction && AppSettings.shared.commandCenterClosesAfterAction
    if closes { close() }
    // Let the popover leave before a capture overlay or window takes over the screen.
    if closes { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { CommandCenterActions.perform(kind) } }
    else { CommandCenterActions.perform(kind) }
  }

  private func frame(for size: CGSize, anchor button: NSStatusBarButton?) -> CGRect {
    let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let visible = screen.visibleFrame
    var midX = visible.midX
    var top = visible.maxY - 6
    if let button, let window = button.window {
      let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
      midX = rect.midX
      top = rect.minY - 6
    }
    let x = min(max(visible.minX + 8, midX - size.width / 2), visible.maxX - size.width - 8)
    return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
  }

  // MARK: Dismissal and keys

  private func installMonitors() {
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
      Task { @MainActor in
        self?.closedByOutsideClickAt = Date()
        self?.close()
      }
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isVisible else { return event }
      switch event.keyCode {
      case 53: // escape
        if self.store.isEditing { self.store.isEditing = false } else { self.close() }
        return nil
      case 123: self.pager.step(-1, count: self.store.pageCount); return nil
      case 124: self.pager.step(1, count: self.store.pageCount); return nil
      default: return event
      }
    }
  }

  private func removeMonitors() {
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    clickMonitor = nil
    keyMonitor = nil
  }
}

/// Borderless and non-activating, so opening the popover never pulls focus from the app in front.
final class CommandCenterPanel: NSPanel {
  init(contentRect: CGRect) {
    super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .statusBar
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
  }
  override var canBecomeKey: Bool { true }
}
