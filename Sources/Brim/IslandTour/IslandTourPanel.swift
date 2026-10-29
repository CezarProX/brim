import AppKit

/// Where the tour card sits: centred a small gap under the island, under its tab bar when open.
enum IslandTourLayout {
  /// Length of the arrow that points from the card up at the island.
  static let arrowLength: CGFloat = 34
  /// Space between the island (or its tab bar) and the card: room for the arrow, and wider than the
  /// island's hover slack, so reaching for the card never reads as the pointer still being on the island.
  static let gap: CGFloat = 14 + arrowLength
  /// Transparent room around the card for its shadow.
  static let shadowMargin: CGFloat = 10

  /// The panel frame, in screen coordinates, for a card of `size` (shadow margin included).
  static func panelFrame(geometry: NotchGeometry, expanded: Bool, size: CGSize) -> CGRect {
    let bottom: CGFloat
    if expanded {
      bottom = geometry.showsNavigation ? geometry.navigationFrame.minY : geometry.panelFrame.minY
    } else {
      bottom = geometry.triggerFrame.minY
    }
    let screen = geometry.screenFrame
    let top = bottom - gap + shadowMargin
    let y = max(screen.minY, top - size.height)
    let x = min(max(screen.minX, screen.midX - size.width / 2), screen.maxX - size.width)
    return CGRect(x: x, y: y, width: size.width, height: size.height).integral
  }
}

/// The tour card's window: borderless and non-activating, above the island, on every Space. It never
/// becomes key, so the app the user is working in keeps focus; its buttons take the first click.
final class IslandTourPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  static func make() -> IslandTourPanel {
    let panel = IslandTourPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isMovable = false
    return panel
  }
}
