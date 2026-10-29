import AppKit
import SwiftUI

/// Two-finger horizontal swipe on a view: next/previous track with an elastic stretch.
/// It listens with a local scroll-wheel monitor so it works on top of any SwiftUI content
/// without stealing clicks, and passes vertical scrolling through untouched.
struct TrackSwipeCatcher: NSViewRepresentable {
  /// Elastic offset (points, signed) while the gesture is live; 0 once it settles.
  @Binding var stretch: CGFloat
  var enabled: Bool
  var reversed: Bool
  var onSwipe: (TrackSwipeDirection) -> Void

  func makeNSView(context: Context) -> CatcherView { CatcherView() }

  func updateNSView(_ view: CatcherView, context: Context) {
    view.enabled = enabled
    view.reversed = reversed
    view.onSwipe = onSwipe
    view.onStretch = { value in DispatchQueue.main.async { stretch = value } }
  }

  static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.removeMonitor() }

  final class CatcherView: NSView {
    var enabled = true
    var reversed = false
    var onSwipe: (TrackSwipeDirection) -> Void = { _ in }
    var onStretch: (CGFloat) -> Void = { _ in }
    private var monitor: Any?
    private var tracker = TrackSwipeTracker()
    private var engaged = false
    private var tickedThisGesture = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      removeMonitor()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        self?.handle(event) ?? event
      }
    }

    func removeMonitor() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    private func handle(_ event: NSEvent) -> NSEvent? {
      guard enabled, event.hasPreciseScrollingDeltas, event.window === window else { return event }
      let inside = bounds.contains(convert(event.locationInWindow, from: nil))
      if event.phase.contains(.began) {
        tracker.reset()
        engaged = false
        tickedThisGesture = false
      }
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        let wasEngaged = engaged
        if let direction = tracker.commit(reversed: reversed), wasEngaged { onSwipe(direction) }
        engaged = false
        onStretch(0)
        return wasEngaged ? nil : event
      }
      guard inside || engaged, !event.momentumPhase.contains(.changed) else { return event }
      tracker.feed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
      let horizontal = abs(tracker.accumulatedX) > 6 && abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
      if horizontal { engaged = true }
      guard engaged else { return event }
      onStretch(tracker.stretch)
      if !tickedThisGesture, abs(tracker.accumulatedX) >= TrackSwipeTracker.threshold {
        tickedThisGesture = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
      }
      return nil
    }
  }
}

extension View {
  /// Adds the track swipe to any media surface; `stretch` should drive an elastic offset.
  func trackSwipe(stretch: Binding<CGFloat>, model: NowPlayingModel? = nil) -> some View {
    let settings = AppSettings.shared
    return background(
      TrackSwipeCatcher(stretch: stretch, enabled: settings.trackSwipeEnabled,
                        reversed: settings.reverseSwipeDirection) { direction in
        let target = model ?? .shared
        direction == .next ? target.next() : target.previous()
      })
  }
}

/// Wraps a surface (artwork, compact wings) with the elastic stretch + swipe in one go.
struct TrackSwipeSurface<Content: View>: View {
  var model: NowPlayingModel?
  @ViewBuilder var content: () -> Content
  @State private var stretch: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    content()
      .trackSwipe(stretch: $stretch, model: model)
      .modifier(ElasticStretch(stretch: stretch, reduceMotion: reduceMotion))
  }
}

/// Rubber-band look shared by the artwork and the compact wings.
struct ElasticStretch: ViewModifier {
  let stretch: CGFloat
  var reduceMotion = false
  /// Size of the stretched element, so the same pull reads equally on small and large art.
  var reference: CGFloat = 90

  func body(content: Content) -> some View {
    content
      .scaleEffect(x: 1 + abs(stretch) / reference, y: 1 - abs(stretch) / (reference * 4),
                   anchor: stretch < 0 ? .trailing : .leading)
      .offset(x: stretch * 0.4)
      .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.72), value: stretch)
  }
}
