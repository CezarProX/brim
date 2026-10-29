import AppKit
import SwiftUI

/// Where the tour's arrow points, worked out from the island's geometry. Pure, so it is unit-tested.
enum IslandTourPointerGeometry {
  /// Width of a tab button in the navigation capsule, and of the Tray tab while it shows a count.
  static let tabWidth: CGFloat = IslandNavigationLayout.item
  static let trayTabWithCount: CGFloat = 9 + 12 + 5 + 17 + 9
  static let tabSpacing: CGFloat = 2

  /// The centre of `page`'s tab inside `capsule`, laid out like `IslandNavigationCapsule`: tabs from
  /// the leading inset, 2 pt apart (favorites sit after them, so they don't move the tabs).
  /// Works in any coordinate space whose x grows to the right.
  static func tabCenter(_ page: IslandPage, pages: [IslandPage], trayCount: Int, capsule: CGRect) -> CGPoint? {
    guard let index = pages.firstIndex(of: page) else { return nil }
    let width: (IslandPage) -> CGFloat = { $0 == .tray && trayCount > 0 ? trayTabWithCount : tabWidth }
    let before = pages[..<index].reduce(CGFloat(0)) { $0 + width($1) + tabSpacing }
    return CGPoint(x: capsule.minX + IslandNavigationLayout.inset + before + width(page) / 2, y: capsule.midY)
  }

  /// The point the arrow's tip touches, in screen coordinates (y up), and whether it is the swipe
  /// hint (drawn on the island) rather than an arrow pointing up from below.
  static func anchor(for target: IslandTourTarget, geometry: NotchGeometry, expanded: Bool,
                     pages: [IslandPage], trayCount: Int) -> (point: CGPoint, swipe: Bool)? {
    switch target {
    case .none:
      return nil
    case .notch:
      guard !expanded else { return nil }
      let notch = geometry.triggerFrame
      return (CGPoint(x: notch.midX, y: notch.minY - 4), false)
    case .tab(let page):
      guard expanded, geometry.showsNavigation,
            let center = tabCenter(page, pages: pages, trayCount: trayCount, capsule: geometry.navigationFrame)
      else { return nil }
      return (CGPoint(x: center.x, y: geometry.navigationFrame.minY - 3), false)
    case .tabBar:
      guard expanded, geometry.showsNavigation else { return nil }
      let bar = geometry.navigationFrame
      return (CGPoint(x: bar.midX, y: bar.minY - 3), false)
    case .islandBody:
      guard expanded else { return nil }
      let body = geometry.panelFrame
      return (CGPoint(x: body.midX, y: body.minY + body.height * 0.42), true)
    }
  }

  /// The click-through window the arrow is drawn in: the top of the display, wide enough for any
  /// island and deep enough to reach under the tallest page's tab bar.
  static func overlayFrame(for geometry: NotchGeometry) -> CGRect {
    let screen = geometry.screenFrame
    let width = min(screen.width, 900)
    let height = min(screen.height, geometry.hostingFrame.height + geometry.topInset + 80)
    return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height).integral
  }
}

/// What the arrow shows; the controller sets the tip in overlay coordinates (top-left origin).
@MainActor
final class IslandTourPointerModel: ObservableObject {
  @Published var tip: CGPoint?
  @Published var swipe = false
}

/// The arrow: points up at a tab or the notch, bobbing gently, with a soft ring pulsing at its tip.
/// For the swipe step it is a two-way chip on the island instead. Static with Reduce Motion.
struct IslandTourPointerView: View {
  @ObservedObject var model: IslandTourPointerModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.clear
      if let tip = model.tip {
        Group {
          if model.swipe { swipeChip } else { arrow }
        }
        .position(x: tip.x, y: tip.y + (model.swipe ? 0 : IslandTourLayout.arrowLength / 2))
        .transition(.opacity)
      }
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.tip)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.swipe)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var arrow: some View {
    VStack(spacing: 0) {
      Image(systemName: "arrowtriangle.up.fill")
        .font(.system(size: 15, weight: .bold))
      Capsule().frame(width: 4, height: IslandTourLayout.arrowLength - 15)
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    .overlay(alignment: .top) { ring.offset(y: -6) }
    .frame(height: IslandTourLayout.arrowLength)
    .modifier(Bob(axis: .vertical, enabled: !reduceMotion))
  }

  private var ring: some View {
    Circle()
      .stroke(Color.white.opacity(0.85), lineWidth: 2)
      .frame(width: 18, height: 18)
      .modifier(Pulse(enabled: !reduceMotion))
  }

  private var swipeChip: some View {
    HStack(spacing: 6) {
      Image(systemName: "chevron.left")
      Image(systemName: "hand.draw.fill").font(.system(size: 15, weight: .semibold))
      Image(systemName: "chevron.right")
    }
    .font(.system(size: 11, weight: .bold))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .frame(height: 32)
    .background(Color.black.opacity(0.55), in: Capsule())
    .overlay { Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1) }
    .modifier(Bob(axis: .horizontal, enabled: !reduceMotion))
  }
}

/// A gentle back-and-forth, up and down for the arrow, sideways for the swipe chip.
private struct Bob: ViewModifier {
  let axis: Axis
  let enabled: Bool

  func body(content: Content) -> some View {
    if enabled {
      content.phaseAnimator([0.0, 1.0]) { view, phase in
        view.offset(x: axis == .horizontal ? (phase - 0.5) * 18 : 0, y: axis == .vertical ? phase * 5 : 0)
      } animation: { _ in .easeInOut(duration: axis == .horizontal ? 0.9 : 0.75) }
    } else {
      content
    }
  }
}

/// The ring at the arrow's tip grows and fades, over and over.
private struct Pulse: ViewModifier {
  let enabled: Bool

  func body(content: Content) -> some View {
    if enabled {
      content.phaseAnimator([false, true]) { view, grown in
        view.scaleEffect(grown ? 1.7 : 0.7).opacity(grown ? 0 : 0.9)
      } animation: { grown in grown ? .easeOut(duration: 1.1) : .linear(duration: 0.01) }
    } else {
      content.opacity(0.6)
    }
  }
}

/// The arrow's window: covers the top of the display but never takes a click, so the island under
/// it works as usual.
final class IslandTourPointerPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  static func make() -> IslandTourPointerPanel {
    let panel = IslandTourPointerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    return panel
  }
}
