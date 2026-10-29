import SwiftUI

/// Home edit mode's drag state and the pure maths behind it: a widget picked up from the row (to
/// reorder) or from the dock (to add where it is dropped), as on an iPhone home screen.
struct HomeEditDrag: Equatable {
  let widget: HomeWidget
  let fromDock: Bool
  var location: CGPoint
  /// Where the pointer grabbed the widget, from its centre, so it does not jump under the pointer.
  let grab: CGSize
}

enum HomeWidgetDrag {
  /// The shelf's coordinate space; every frame and drag location is measured in it.
  static let space = "homeShelf"

  /// Where a widget dropped at `x` lands among the widgets in `order` (the dragged one excluded):
  /// before the first whose middle is right of the pointer.
  static func insertionIndex(x: CGFloat, order: [HomeWidget], frames: [HomeWidget: CGRect],
                             dragging: HomeWidget?) -> Int {
    let others = order.filter { $0 != dragging }
    return others.firstIndex { (frames[$0]?.midX ?? .infinity) > x } ?? others.count
  }

  /// Turns an index among the visible widgets (the page in view) into one among all widgets.
  static func globalIndex(_ index: Int, visible: [HomeWidget], all: [HomeWidget], dragging: HomeWidget) -> Int {
    let others = all.filter { $0 != dragging }
    let shown = visible.filter { $0 != dragging }
    if index < shown.count, let at = others.firstIndex(of: shown[index]) { return at }
    if let last = shown.last, let at = others.firstIndex(of: last) { return at + 1 }
    return others.count
  }

  /// The gap a drop would fill, as an x position between widget frames (for the insertion bar).
  static func caretX(index: Int, order: [HomeWidget], frames: [HomeWidget: CGRect], dragging: HomeWidget?) -> CGFloat? {
    let others = order.filter { $0 != dragging }.compactMap { frames[$0] }
    guard !others.isEmpty else { return nil }
    if index <= 0 { return others[0].minX - HomeWidgetGrid.gap / 2 }
    if index >= others.count { return others[others.count - 1].maxX + HomeWidgetGrid.gap / 2 }
    return (others[index - 1].maxX + others[index].minX) / 2
  }
}

/// Each widget cell reports its frame in the shelf's space.
struct HomeWidgetFramesKey: PreferenceKey {
  static let defaultValue: [HomeWidget: CGRect] = [:]
  static func reduce(value: inout [HomeWidget: CGRect], nextValue: () -> [HomeWidget: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

extension View {
  func reportsHomeWidgetFrame(_ widget: HomeWidget) -> some View {
    background {
      GeometryReader { proxy in
        Color.clear.preference(key: HomeWidgetFramesKey.self,
                               value: [widget: proxy.frame(in: .named(HomeWidgetDrag.space))])
      }
    }
  }
}

// MARK: Edit-mode chrome

/// The red − on a widget's top-left corner while editing, as on an iPhone home screen.
struct HomeRemoveBadge: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "minus").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
        .frame(width: 18, height: 18).background(Color.red, in: Circle())
        .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5) }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.95))
    .accessibilityLabel("Remove \(title)")
  }
}

/// The resize handle on a widget's bottom-right corner while editing: one click switches between
/// small and medium. Dimmed when the other size would not fit the pages.
struct HomeResizeHandle: View {
  let title: String
  /// True when the click makes the widget bigger.
  let grows: Bool
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: grows ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
        .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
        .frame(width: 20, height: 20).background(Color.white, in: Circle())
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.95))
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
    .help(grows ? "Make \(title) larger" : "Make \(title) smaller")
    .accessibilityLabel(grows ? "Make \(title) larger" : "Make \(title) smaller")
  }
}

/// iOS-style home-screen wobble while editing. Driven by a timeline rather than a repeating
/// animation, so it can never leak into the island's own layout transitions. Callers pass
/// `active: false` under Reduce Motion.
struct HomeJiggle: ViewModifier {
  let active: Bool
  let seed: Int

  /// One structure whether or not it wobbles: switching between two branches would rebuild the
  /// widget, and a drag that starts on it (which stops its wobble) would be cancelled at once.
  func body(content: Content) -> some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      content.rotationEffect(.degrees(active ? 0.9 * sin(time * 22 + Double(seed)) : 0))
    }
  }
}
