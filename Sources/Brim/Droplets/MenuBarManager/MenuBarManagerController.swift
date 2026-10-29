import AppKit

/// Hide / show menu bar items: a best-effort take on Thaw and Hidden Bar.
///
/// Honest limits: macOS offers no API to move other apps' items, so you place the separator by
/// holding ⌘ and dragging items to its left. Collapsing hides only what is left of the separator,
/// and a notch Mac may still hide items on its own when the bar is crowded.
@MainActor
final class MenuBarManagerController: ObservableObject {
  static let shared = MenuBarManagerController()

  @Published private(set) var isCollapsed = false
  @Published private(set) var isRunning = false
  @Published private(set) var lastNotice: String?

  private var toggleItem: NSStatusItem?
  private var separatorItem: NSStatusItem?
  private var expandedAt: Date?
  private var timer: Timer?
  private let hotkey = DropletHotkey()
  private let settings = AppSettings.shared

  /// Brings the manager in line with the settings: items + shortcut when enabled, none otherwise.
  func start() {
    hotkey.unregister()
    guard settings.menuBarManagerEnabled else { teardown(); return }
    if !isRunning { install() }
    hotkey.onPress = { [weak self] in self?.toggle() }
    let shortcut = settings.menuBarManagerShortcut
    if shortcut.isSet, !hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
      IslandFlashCenter.shared.show("Menu bar shortcut is taken", symbol: "menubar.rectangle", tint: .orange)
    }
  }

  /// One-tap turn on from the island: saves the setting and installs the divider and arrow.
  func enable() {
    settings.menuBarManagerEnabled = true
    start()
  }

  func disable() {
    settings.menuBarManagerEnabled = false
    start()
  }

  func shutdown() { hotkey.unregister(); teardown() }

  func toggle() {
    guard isRunning else {
      IslandFlashCenter.shared.show("Turn on Menu Bar Manager in Settings", symbol: "menubar.rectangle", tint: .orange)
      return
    }
    setCollapsed(!isCollapsed)
  }

  private func install() {
    // Created right-to-left: the toggle first (rightmost), then the separator to its left.
    let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let separator = NSStatusBar.system.statusItem(withLength: HiddenBarPolicy.expandedLength)
    toggle.autosaveName = "BrimMenuBarToggle"
    separator.autosaveName = "BrimMenuBarSeparator"
    toggle.button?.target = self
    toggle.button?.action = #selector(toggleClicked)
    toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    separator.button?.image = Self.dividerImage()
    toggleItem = toggle
    separatorItem = separator
    isRunning = true
    isCollapsed = false
    render()
    if settings.menuBarManagerStartCollapsed {
      // Items need a moment to take their saved positions before the order can be checked.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.setCollapsed(true) }
    }
  }

  private func teardown() {
    timer?.invalidate()
    timer = nil
    if let toggleItem { NSStatusBar.system.removeStatusItem(toggleItem) }
    if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
    toggleItem = nil
    separatorItem = nil
    isRunning = false
    isCollapsed = false
  }

  @objc private func toggleClicked() { toggle() }

  func setCollapsed(_ collapsed: Bool) {
    guard isRunning else { return }
    if collapsed {
      let separatorX = separatorItem?.button?.window?.frame.minX
      let toggleX = toggleItem?.button?.window?.frame.minX
      guard HiddenBarPolicy.canCollapse(separatorMinX: separatorX, toggleMinX: toggleX) else {
        lastNotice = "Hold ⌘ and drag the divider to the left of the arrow first."
        IslandFlashCenter.shared.show("Move the divider left of the arrow", symbol: "menubar.arrow.up.rectangle", tint: .orange, detail: "Hold ⌘ and drag it")
        return
      }
    }
    lastNotice = nil
    isCollapsed = collapsed
    expandedAt = collapsed ? nil : .now
    render()
    scheduleRehide()
  }

  private func render() {
    let widest = NSScreen.screens.map(\.frame.width).max() ?? 1920
    separatorItem?.length = HiddenBarPolicy.separatorLength(collapsed: isCollapsed, widestScreen: widest)
    separatorItem?.button?.image = isCollapsed ? nil : Self.dividerImage()
    let symbol = HiddenBarPolicy.toggleSymbol(collapsed: isCollapsed)
    toggleItem?.button?.image = NSImage(
      systemSymbolName: symbol, accessibilityDescription: isCollapsed ? "Show hidden menu bar items" : "Hide menu bar items")
  }

  private func scheduleRehide() {
    timer?.invalidate()
    timer = nil
    guard !isCollapsed, settings.menuBarManagerAutoRehide else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if HiddenBarPolicy.shouldAutoCollapse(
          expandedAt: self.expandedAt, now: .now, delay: TimeInterval(self.settings.menuBarManagerRehideSeconds), enabled: true)
        {
          self.setCollapsed(true)
        }
      }
    }
  }

  private static func dividerImage() -> NSImage? {
    let divider = NSImage(size: NSSize(width: 6, height: 16), flipped: false) { rect in
      NSColor.labelColor.withAlphaComponent(0.35).setFill()
      NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2, width: 1, height: 12), xRadius: 0.5, yRadius: 0.5).fill()
      return true
    }
    divider.isTemplate = true
    return divider
  }
}
