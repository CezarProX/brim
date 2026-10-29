import AppKit
import SwiftUI

/// Where a horizontal scroll view is: how far it has scrolled, how much content it holds, how much
/// of it shows. Drives both the tab-swipe gate and the wheel adapter.
struct HorizontalScrollExtent: Equatable {
  var offset: CGFloat
  var content: CGFloat
  var viewport: CGFloat

  private static let slack: CGFloat = 1
  var overflows: Bool { content - viewport > Self.slack }
  var canScrollBackward: Bool { offset > Self.slack }
  var canScrollForward: Bool { offset < content - viewport - Self.slack }
}

/// Decides, once per two-finger gesture, whether the island may turn the page or the content
/// underneath keeps the gesture. Over a horizontal scroller the content wins, unless it already sits
/// at the edge the fingers push toward, so a swipe from the last card still reaches the next tab.
struct IslandSwipeGate {
  /// What lies under the pointer when a gesture starts.
  enum Region: Equatable {
    /// Plain content or the tab bar: the island's page swipe applies.
    case none
    /// Horizontally scrolling content.
    case scroller(HorizontalScrollExtent)
    /// Editing surface: nothing here changes the page.
    case blocker
  }

  private var decided = false
  private var allowed = true

  /// `region` is only evaluated while the gesture's direction is still unknown.
  mutating func allows(dx: CGFloat, dy: CGFloat, phase: SwipeTracker.Phase, region: () -> Region) -> Bool {
    if phase == .began { self = IslandSwipeGate() }
    defer { if phase == .ended { self = IslandSwipeGate() } }
    if decided { return allowed }
    guard abs(dx) + abs(dy) > 0.5 else { return true }
    decided = true
    guard abs(dx) > abs(dy) else { return true }
    switch region() {
    case .none: allowed = true
    case .blocker: allowed = false
    case .scroller(let extent):
      // Swiping left (dx < 0) pulls content toward its end and moves to the next page.
      allowed = !extent.overflows || (dx < 0 ? !extent.canScrollForward : !extent.canScrollBackward)
    }
    return allowed
  }
}

/// A mouse wheel only has a vertical axis; horizontal strips read it as sideways travel.
enum IslandWheelMapping {
  /// Points a plain wheel notch moves a horizontal strip.
  static let notchPoints: CGFloat = 32

  /// How far to move the content offset for a phaseless wheel event, or nil when the event is not
  /// a vertical wheel turn (leave it alone). Wheel down (negative `dy`) moves toward the end.
  static func offsetDelta(dx: CGFloat, dy: CGFloat, precise: Bool) -> CGFloat? {
    guard dy != 0, abs(dy) > abs(dx) else { return nil }
    return -dy * (precise ? 1 : notchPoints)
  }

  static func clamped(_ offset: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
    min(max(offset, 0), max(content - viewport, 0))
  }
}

/// The registry of views that claim horizontal scrolling. The shell's swipe consults it by screen
/// point; a single local monitor feeds wheel events to the region under the pointer.
@MainActor
final class IslandScrollRegions {
  static let shared = IslandScrollRegions()

  enum Mode {
    /// A horizontal ScrollView: trackpad scrolls it natively, the wheel is mapped sideways.
    case scroller
    /// Pages with their own step handler (Home grid): the wheel turns a page.
    case pager(step: (Int) -> Void)
    /// Swallows page swipes without scrolling anything (Home while editing).
    case blocker
  }

  fileprivate final class Entry {
    weak var view: RegionView?
  }

  fileprivate var entries: [Entry] = []
  private var monitor: Any?

  fileprivate func register(_ view: RegionView) {
    entries.removeAll { $0.view == nil || $0.view === view }
    let entry = Entry()
    entry.view = view
    entries.append(entry)
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      MainActor.assumeIsolated { IslandScrollRegions.shared.handleWheel(event) ? nil : event }
    }
  }

  /// What the swipe gate sees at a screen point: the smallest region containing it wins.
  func region(atScreen point: CGPoint) -> IslandSwipeGate.Region {
    // A blocker wins over any scroller inside it: editing never turns the page, even from an edge.
    if live.contains(where: { if case .blocker = $0.mode { return $0.contains(screen: point) } else { return false } }) {
      return .blocker
    }
    guard let view = view(atScreen: point) else { return .none }
    guard let scroll = view.scrollView(atScreen: point), let extent = Self.extent(of: scroll) else { return .none }
    return .scroller(extent)
  }

  private var live: [RegionView] {
    entries.removeAll { $0.view == nil }
    return entries.compactMap(\.view)
  }

  private func view(atScreen point: CGPoint) -> RegionView? {
    live.filter { $0.contains(screen: point) }
      .min { $0.screenFrame.width * $0.screenFrame.height < $1.screenFrame.width * $1.screenFrame.height }
  }

  fileprivate static func extent(of scroll: NSScrollView) -> HorizontalScrollExtent? {
    guard let document = scroll.documentView else { return nil }
    let clip = scroll.contentView
    return HorizontalScrollExtent(offset: clip.bounds.origin.x, content: document.frame.width, viewport: clip.bounds.width)
  }

  /// Returns true when the wheel event was used.
  private func handleWheel(_ event: NSEvent) -> Bool {
    guard event.phase.isEmpty, event.momentumPhase.isEmpty, let window = event.window else { return false }
    let point = window.convertPoint(toScreen: event.locationInWindow)
    guard let view = view(atScreen: point), view.window === window else { return false }
    switch view.mode {
    case .blocker:
      return false
    case .pager(let step):
      let outcome = view.pager.wheel(dy: event.scrollingDeltaY, dx: event.scrollingDeltaX,
                                     precise: event.hasPreciseScrollingDeltas, now: ProcessInfo.processInfo.systemUptime)
      switch outcome {
      case .pass: return false
      case .hold: return true
      case .step(let delta): step(delta); return true
      }
    case .scroller:
      guard let scroll = view.scrollView(atScreen: point), let extent = Self.extent(of: scroll), extent.overflows,
            let delta = IslandWheelMapping.offsetDelta(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                                       precise: event.hasPreciseScrollingDeltas)
      else { return false }
      let clip = scroll.contentView
      var origin = clip.bounds.origin
      origin.x = IslandWheelMapping.clamped(origin.x + delta, content: extent.content, viewport: extent.viewport)
      clip.scroll(to: origin)
      scroll.reflectScrolledClipView(clip)
      return true
    }
  }

  fileprivate final class RegionView: NSView {
    var mode: Mode = .scroller
    var pager = IslandWidgetPager()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil { IslandScrollRegions.shared.register(self) }
    }

    func contains(screen point: CGPoint) -> Bool {
      window != nil && !isHiddenOrHasHiddenAncestor && screenFrame.contains(point)
    }

    var screenFrame: CGRect {
      guard let window else { return .zero }
      return window.convertToScreen(convert(bounds, to: nil))
    }

    /// The NSScrollView SwiftUI built for this region: the smallest one holding the point.
    func scrollView(atScreen point: CGPoint) -> NSScrollView? {
      guard let root = window?.contentView else { return nil }
      var best: NSScrollView?
      var stack: [NSView] = [root]
      while let view = stack.popLast() {
        stack.append(contentsOf: view.subviews)
        guard let scroll = view as? NSScrollView, let window = scroll.window,
              window.convertToScreen(scroll.convert(scroll.bounds, to: nil)).contains(point) else { continue }
        // Prefer a scroll view that actually scrolls sideways, then the smallest.
        let candidateScrolls = Self.extentOverflows(scroll)
        guard let current = best else { best = scroll; continue }
        let bestScrolls = Self.extentOverflows(current)
        if candidateScrolls != bestScrolls { if candidateScrolls { best = scroll } }
        else if scroll.bounds.width * scroll.bounds.height < current.bounds.width * current.bounds.height { best = scroll }
      }
      return best
    }

    private static func extentOverflows(_ scroll: NSScrollView) -> Bool {
      IslandScrollRegions.extent(of: scroll)?.overflows ?? false
    }
  }

  struct Marker: NSViewRepresentable {
    let mode: Mode

    func makeNSView(context: Context) -> NSView {
      let view = RegionView()
      view.mode = mode
      return view
    }

    func updateNSView(_ view: NSView, context: Context) { (view as? RegionView)?.mode = mode }
  }
}

extension View {
  /// Marks this view as a horizontal scroller (or pager, or editing blocker) so a two-finger swipe
  /// over it scrolls it instead of switching the island's tab, and the mouse wheel drives it.
  func islandScrollRegion(_ mode: IslandScrollRegions.Mode = .scroller) -> some View {
    background(IslandScrollRegions.Marker(mode: mode))
  }
}
