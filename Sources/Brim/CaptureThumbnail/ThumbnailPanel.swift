import AppKit
import SwiftUI

/// A borderless, non-activating panel for one thumbnail: above normal windows, on every Space and
/// beside full-screen apps, and never key, so it does not take focus from the app being used.
final class ThumbnailPanel: NSPanel {
  init(frame: CGRect) {
    super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    hidesOnDeactivate = false
    isMovable = false
    isReleasedWhenClosed = false
    becomesKeyOnlyIfNeeded = true
    animationBehavior = .none
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Clicks land on the first try even though Brim is not the active app.
final class ThumbnailHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
