import AppKit
import Testing

@testable import Brim

/// Real mouse events must reach the capture overlay and the onboarding window.
@MainActor
@Suite(.serialized)
struct MouseDeliveryTests {
  private func event(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  }

  private func drag(in window: NSWindow, from: CGPoint, to: CGPoint, viaApp: Bool) {
    let send: (NSEvent) -> Void = { viaApp ? NSApp.sendEvent($0) : window.sendEvent($0) }
    send(event(.leftMouseDown, at: from, in: window))
    send(event(.leftMouseDragged, at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), in: window))
    send(event(.leftMouseDragged, at: to, in: window))
    send(event(.leftMouseUp, at: to, in: window))
  }

  @Test(arguments: [false, true])
  func overlayDragSelectsOnEveryDisplay(viaApp: Bool) {
    _ = NSApplication.shared
    let controller = OverlayController.shared
    let screens = NSScreen.screens
    for screen in screens {
      controller.begin(screens: screens, frozenImages: [:])
      defer { controller.dismiss() }
      let window = try! #require(controller.windowFor(screen))
      let size = screen.frame.size
      drag(in: window, from: CGPoint(x: size.width * 0.2, y: size.height * 0.2),
           to: CGPoint(x: size.width * 0.6, y: size.height * 0.6), viaApp: viaApp)
      #expect(controller.activeScreen == screen, "no active screen after drag on \(screen.frame)")
      let rect = controller.selectionRect
      #expect(rect != nil && rect!.width > 100, "no selection after drag on \(screen.frame): \(String(describing: rect))")
    }
  }

  /// Same, but with the island panels' idle state in the way (they live in the app while a capture runs).
  @Test func overlayWindowIsFrontmostAtItsPoint() {
    _ = NSApplication.shared
    let controller = OverlayController.shared
    controller.begin(screens: NSScreen.screens, frozenImages: [:])
    defer { controller.dismiss() }
    for (screen, window) in controller.windows {
      #expect(window.frame == screen.frame)
      #expect(!window.ignoresMouseEvents)
      #expect(window.contentView?.hitTest(CGPoint(x: 50, y: 50)) is SelectionOverlayView)
    }
  }
}

extension MouseDeliveryTests {
  /// Wispr Flow's transparent status window sits at level 1000 over the screen centre and ate clicks.
  @Test func overlayRidesAboveScreenSaverLevelWindows() {
    #expect(OverlayWindow.captureLevel.rawValue > NSWindow.Level.screenSaver.rawValue + 1)
  }
}
