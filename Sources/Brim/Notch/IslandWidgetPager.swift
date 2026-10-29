import AppKit
import SwiftUI

/// Turns scroll input into whole-page steps for the widget grid. A trackpad gesture moves at most
/// one page once it travels far enough; a mouse wheel moves one page per notch, with a short pause
/// so a fast spin doesn't skip pages. Horizontal gestures stay with the island's page swipe.
struct IslandWidgetPager {
  /// Trackpad travel (points) before a gesture turns the page.
  static let threshold: CGFloat = 24
  /// Pause after a mouse-wheel step before the next notch counts.
  static let wheelCooldown: TimeInterval = 0.28

  enum Outcome: Equatable {
    /// Not ours: let the event through (horizontal swipe, idle momentum).
    case pass
    /// Ours, nothing to do yet: swallow it so nothing else scrolls.
    case hold
    /// Move by this many pages (+1 = down).
    case step(Int)
  }

  private var travel: CGFloat = 0
  private var decided = false
  private var vertical = false
  private var steppedThisGesture = false
  private var lastWheelStep: TimeInterval = -.infinity
  private var lastWheelEvent: TimeInterval = -.infinity
  private var wheelTravel: CGFloat = 0

  /// One trackpad event: `dy` is AppKit's `scrollingDeltaY`, negative when scrolling down.
  mutating func trackpad(dy: CGFloat, dx: CGFloat, began: Bool, ended: Bool, momentum: Bool) -> Outcome {
    if began { resetGesture() }
    if momentum { return vertical ? .hold : .pass }
    if ended {
      defer { resetGesture() }
      return vertical ? .hold : .pass
    }
    if !decided, abs(dx) + abs(dy) > 0.5 {
      decided = true
      vertical = abs(dy) >= abs(dx)
    }
    guard vertical else { return .pass }
    travel += dy
    guard !steppedThisGesture, abs(travel) >= Self.threshold else { return .hold }
    steppedThisGesture = true
    return .step(travel < 0 ? 1 : -1)
  }

  /// One wheel event without a gesture phase at time `now` (seconds, any monotonic clock). A plain
  /// notch turns the page; `precise` deltas (smooth-scrolling mice, LinearMouse, Mos) add up to
  /// `threshold` first, since they arrive as many small pixel steps.
  mutating func wheel(dy: CGFloat, dx: CGFloat, precise: Bool = false, now: TimeInterval) -> Outcome {
    guard abs(dy) > abs(dx), dy != 0 else { return .pass }
    if now - lastWheelEvent > Self.wheelCooldown { wheelTravel = 0 }
    lastWheelEvent = now
    guard now - lastWheelStep >= Self.wheelCooldown else { return .hold }
    wheelTravel += dy
    guard !precise || abs(wheelTravel) >= Self.threshold else { return .hold }
    defer { wheelTravel = 0 }
    lastWheelStep = now
    return .step(wheelTravel < 0 ? 1 : -1)
  }

  private mutating func resetGesture() {
    travel = 0
    decided = false
    vertical = false
    steppedThisGesture = false
  }
}

/// Listens for scrolling over the grid with a local monitor, so tiles keep their hover and clicks.
struct IslandWidgetPageCatcher: NSViewRepresentable {
  var onStep: (Int) -> Void

  func makeNSView(context: Context) -> CatcherView { CatcherView() }

  func updateNSView(_ view: CatcherView, context: Context) { view.onStep = onStep }

  static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.removeMonitor() }

  final class CatcherView: NSView {
    var onStep: (Int) -> Void = { _ in }
    private var monitor: Any?
    private var pager = IslandWidgetPager()
    /// A trackpad gesture that started over the grid stays ours until it ends.
    private var engaged = false

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
      guard event.window === window else { return event }
      let inside = bounds.contains(convert(event.locationInWindow, from: nil))
      let outcome: IslandWidgetPager.Outcome
      // Trackpads and the Magic Mouse send phased gestures; wheels, including smooth-scrolling
      // tools that fake precise deltas, send phaseless events.
      if !event.phase.isEmpty || !event.momentumPhase.isEmpty {
        let began = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        if began { engaged = inside }
        guard engaged else { return event }
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        let momentum = !event.momentumPhase.isEmpty
        outcome = pager.trackpad(dy: event.scrollingDeltaY, dx: event.scrollingDeltaX,
                                 began: began, ended: ended, momentum: momentum)
        if momentum && event.momentumPhase.contains(.ended) { engaged = false }
      } else {
        guard inside else { return event }
        outcome = pager.wheel(dy: event.scrollingDeltaY, dx: event.scrollingDeltaX,
                              precise: event.hasPreciseScrollingDeltas, now: ProcessInfo.processInfo.systemUptime)
      }
      switch outcome {
      case .pass: return event
      case .hold: return nil
      case .step(let delta):
        onStep(delta)
        return nil
      }
    }
  }
}

/// Small vertical dots beside the grid: where you are, and a click to jump.
struct IslandWidgetPageDots: View {
  let count: Int
  let current: Int
  let select: (Int) -> Void

  var body: some View {
    VStack(spacing: 7) {
      ForEach(0..<count, id: \.self) { index in
        Button { select(index) } label: {
          Capsule()
            .fill(index == current ? IslandInk.primary : IslandInk.tertiary.opacity(0.6))
            .frame(width: 6, height: index == current ? 16 : 6)
            .frame(width: 14, height: index == current ? 18 : 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.85))
        .accessibilityLabel("Page \(index + 1) of \(count)")
        .accessibilityAddTraits(index == current ? .isSelected : [])
      }
    }
  }
}
