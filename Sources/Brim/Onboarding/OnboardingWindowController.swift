import AppKit
import SwiftUI

/// Where the tour window goes: centered on a screen, scaled down only if the screen is too small,
/// and always below the menu bar and notch so it never covers the island.
enum OnboardingPlacement {
  static let margin: CGFloat = 16

  static func layout(size: CGSize, visibleFrame: CGRect) -> (frame: CGRect, scale: CGFloat) {
    let scale = max(0.5, min(1, (visibleFrame.height - margin * 2) / size.height, (visibleFrame.width - margin * 2) / size.width))
    let scaled = CGSize(width: size.width * scale, height: size.height * scale)
    let x = visibleFrame.midX - scaled.width / 2
    let centeredY = visibleFrame.midY - scaled.height / 2
    let y = max(visibleFrame.minY, min(centeredY, visibleFrame.maxY - margin - scaled.height))
    return (CGRect(origin: CGPoint(x: x, y: y), size: scaled), scale)
  }

  /// The screen the pointer is on, else the main one.
  @MainActor static func currentScreen() -> NSScreen? {
    let point = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
  }
}

/// Keys the tour handles itself.
enum OnboardingKey {
  case back, forward, close

  static func from(keyCode: UInt16) -> OnboardingKey? {
    switch keyCode {
    case 123: .back
    case 124: .forward
    case 53: .close
    default: nil
    }
  }
}

/// Shows the first-run tour, and replays it from Settings > About.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
  static let shared = OnboardingWindowController()
  private var window: NSWindow?
  private let flow = OnboardingFlow()
  private let settings: AppSettings
  private let revealIsland: () -> Void
  private let startIslandTour: (TimeInterval) -> Void

  init(settings: AppSettings = .shared,
       revealIsland: (() -> Void)? = nil,
       startIslandTour: ((TimeInterval) -> Void)? = nil) {
    self.settings = settings
    self.revealIsland = revealIsland ?? { NotchShelfController.shared.showIsland() }
    self.startIslandTour = startIslandTour ?? { IslandTourController.shared.startIfNeeded(after: $0) }
    super.init()
  }

  /// First launch only: opens the tour until the user has finished or closed it once.
  func showIfNeeded() {
    guard !settings.onboardingCompleted else {
      // Saw the introduction before the Island Tour existed: offer the tour once, after launch settles.
      startIslandTour(IslandTourPolicy.launchDelay)
      return
    }
    show()
  }

  func show() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }
    _ = OnboardingArt.shared
    flow.go(to: 0)
    let visible = OnboardingPlacement.currentScreen()?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 860)
    let placed = OnboardingPlacement.layout(size: OnboardingView.size, visibleFrame: visible)
    let root = OnboardingRoot(flow: flow, scale: placed.scale, onFinish: { [weak self] in self?.finish() })
    let host = FirstClickHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: placed.frame.size)
    let window = OnboardingWindow(contentRect: placed.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.delegate = self
    window.onKey = { [weak self] key in self?.handle(key) }
    window.setFrame(placed.frame, display: false)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func handle(_ key: OnboardingKey) {
    switch key {
    case .back: flow.step(-1)
    case .forward: flow.step(1)
    case .close: finish()
    }
  }

  private func finish() {
    let firstLaunch = !settings.onboardingCompleted
    settings.onboardingCompleted = true
    window?.orderOut(nil)
    window = nil
    // Make the real island discoverable even if another app is fullscreen or no grants were given.
    if firstLaunch && settings.notchShelfEnabled { revealIsland() }
    // The first time through, the introduction hands over to the Island Tour on the real island.
    startIslandTour(IslandTourPolicy.afterIntroductionDelay)
  }
}

/// Builds the sample song, then shows the tour, scaled when the screen is small.
private struct OnboardingRoot: View {
  let flow: OnboardingFlow
  let scale: CGFloat
  let onFinish: () -> Void

  var body: some View {
    OnboardingView(flow: flow, onFinish: onFinish)
      .scaleEffect(scale, anchor: .topLeading)
      .frame(width: OnboardingView.size.width * scale, height: OnboardingView.size.height * scale, alignment: .topLeading)
  }
}

/// A borderless window can't become key by default, which left the tour's buttons dead after a click
/// and made it impossible to move. This one takes key focus, drags by its top band, and reads Esc and the arrows.
final class OnboardingWindow: NSWindow {
  /// Height of the band along the top edge that drags the window, clear of the corner buttons.
  private static let dragBand: CGFloat = 40
  var onKey: ((OnboardingKey) -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown { InputTrace.event("onboarding.window.sendEvent", event, window: self) }
    if event.type == .leftMouseDown, isInDragBand(event.locationInWindow) {
      performDrag(with: event)
      return
    }
    super.sendEvent(event)
  }

  override func keyDown(with event: NSEvent) {
    if let key = OnboardingKey.from(keyCode: event.keyCode) { onKey?(key) } else { super.keyDown(with: event) }
  }

  override func cancelOperation(_ sender: Any?) { onKey?(.close) }

  private func isInDragBand(_ point: NSPoint) -> Bool {
    let size = frame.size
    return point.y >= size.height - Self.dragBand && point.x > 64 && point.x < size.width - 64
  }
}

/// Lets the first click on a window of this background app reach the SwiftUI control under it
/// instead of only bringing the app forward.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
