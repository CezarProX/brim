import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows the Action Ring: a radial menu at the pointer with up to three customizable rings.
///
/// Opening: the ⌥⌘R shortcut (`toggle()`), or, when enabled in settings, holding a lone modifier
/// (`start()` installs the monitor). In "hold to open" mode the slot under the pointer runs when
/// the shortcut key is released; a quick tap leaves the ring open to click instead.
@MainActor
final class RingMenuController: NSObject, NSWindowDelegate {
  static let shared = RingMenuController()
  private var panel: RingPanel?
  private var model: RingViewModel?
  private var releaseTimer: Timer?
  private var modifierMonitor: Any?
  private var modifierTimer: Timer?
  private var openedAt = Date()
  private var scrollAccumulator: CGFloat = 0
  private let settings = AppSettings.shared

  /// Installs the hold-modifier opener if it is enabled. Safe to call again after the setting changes.
  func start() {
    if let monitor = modifierMonitor { NSEvent.removeMonitor(monitor) }
    modifierMonitor = nil
    guard settings.ringHoldModifier != .off else { return }
    modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      Task { @MainActor in self?.modifiersChanged(flags) }
    }
  }

  func toggle() {
    guard panel == nil else { return close() }
    show(at: NSEvent.mouseLocation)
    if settings.ringTriggerMode == .holdAndRelease { watchShortcutRelease(keyCode: kVK_ANSI_R) }
  }

  func show(at point: CGPoint) {
    close()
    let viewModel = RingViewModel(layout: settings.ringLayout)
    viewModel.onChoose = { [weak self] slot in
      self?.close()
      Task { @MainActor in await RingActionRunner.run(slot) }
    }
    let side = RingView.side
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let origin = CGPoint(
      x: min(max(point.x - side / 2, bounds.minX), bounds.maxX - side),
      y: min(max(point.y - side / 2, bounds.minY), bounds.maxY - side))
    let panel = RingPanel(
      contentRect: CGRect(origin: origin, size: CGSize(width: side, height: side)),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.close() }
    panel.onScroll = { [weak self] delta in self?.scrolled(delta) }
    panel.onNumber = { [weak viewModel] number in viewModel?.selectRing(number: number) }
    panel.contentView = NSHostingView(rootView: RingView(model: viewModel))
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
    self.model = viewModel
    openedAt = Date()
  }

  func close() {
    releaseTimer?.invalidate()
    releaseTimer = nil
    guard let panel else { return }
    self.panel = nil
    self.model = nil
    panel.delegate = nil
    panel.orderOut(nil)
  }

  func windowDidResignKey(_ notification: Notification) { close() }

  // MARK: Scrolling between rings

  private func scrolled(_ delta: CGFloat) {
    scrollAccumulator += delta
    guard abs(scrollAccumulator) >= 4 else { return }
    model?.switchRing(step: scrollAccumulator > 0 ? -1 : 1)
    scrollAccumulator = 0
  }

  // MARK: Hold to open, release to choose

  /// Polls the key state (no permission needed) until the shortcut key is let go.
  private func watchShortcutRelease(keyCode: Int) {
    releaseTimer?.invalidate()
    releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.panel != nil else { return }
        let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        if !down { self.released() }
      }
    }
  }

  private func released() {
    releaseTimer?.invalidate()
    releaseTimer = nil
    // A tap that was over in a blink leaves the ring open for clicking.
    guard Date().timeIntervalSince(openedAt) > 0.28 else { return }
    if model?.chooseHovered() != true { close() }
  }

  // MARK: Hold a lone modifier to open

  private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
    modifierTimer?.invalidate()
    modifierTimer = nil
    let wanted: NSEvent.ModifierFlags
    switch settings.ringHoldModifier {
    case .off: return
    case .option: wanted = .option
    case .control: wanted = .control
    case .shift: wanted = .shift
    }
    guard flags == wanted, panel == nil else { return }
    modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.openFromModifier(wanted) }
    }
  }

  private func openFromModifier(_ modifier: NSEvent.ModifierFlags) {
    guard panel == nil else { return }
    show(at: NSEvent.mouseLocation)
    releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.panel != nil else { return }
        let held = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !held.contains(modifier) {
          self.releaseTimer?.invalidate()
          self.releaseTimer = nil
          if self.model?.chooseHovered() != true { self.close() }
        }
      }
    }
  }
}

/// Becomes key so Escape, number keys, scrolling and clicking elsewhere work.
private final class RingPanel: NSPanel {
  var onCancel: (() -> Void)?
  var onScroll: ((CGFloat) -> Void)?
  var onNumber: ((Int) -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel?() }
  override func scrollWheel(with event: NSEvent) {
    onScroll?(event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY)
  }
  override func keyDown(with event: NSEvent) {
    if let text = event.charactersIgnoringModifiers, let number = Int(text), (1...3).contains(number) {
      onNumber?(number)
    } else {
      super.keyDown(with: event)
    }
  }
}
