import SwiftUI

/// State of the open ring: which ring is showing, where the pointer points, what is chosen.
@MainActor
final class RingViewModel: ObservableObject {
  @Published private(set) var layout: RingLayout
  @Published private(set) var ringIndex = 0
  @Published private(set) var hovered: Int?
  /// Continuous (unwrapped) highlight angle in degrees, so the wedge glides between slots.
  @Published private(set) var highlightAngle: Double = 0
  @Published var appeared = false
  /// Direction of the last ring switch, for the slide transition.
  @Published private(set) var switchStep = 1
  var onChoose: (RingSlot) -> Void = { _ in }

  init(layout: RingLayout) { self.layout = layout }

  var ring: RingPage { layout.rings[ringIndex] }
  var slots: [RingSlot?] { ring.slots }
  var hoveredSlot: RingSlot? { hovered.flatMap { slots[$0] } }

  func pointerMoved(dx: CGFloat, dy: CGFloat) {
    let index = RingGeometry.slot(dx: dx, dy: dy, count: RingPage.slotCount)
    let next = index.flatMap { slots[$0] == nil ? nil : $0 }
    if let next {
      let target = RingGeometry.centerAngle(index: next, count: RingPage.slotCount)
      highlightAngle = RingGeometry.unwrapped(previous: highlightAngle, target: target)
    }
    if hovered != next { hovered = next }
  }

  func pointerLeft() { hovered = nil }

  func switchRing(step: Int) {
    let next = RingGeometry.ring(after: ringIndex, step: step, count: layout.rings.count)
    guard next != ringIndex else { return }
    switchStep = step >= 0 ? 1 : -1
    ringIndex = next
    hovered = nil
  }

  /// Number keys: 1...3 jump to that ring when it exists.
  func selectRing(number: Int) {
    let target = number - 1
    guard layout.rings.indices.contains(target), target != ringIndex else { return }
    switchStep = target > ringIndex ? 1 : -1
    ringIndex = target
    hovered = nil
  }

  /// Runs the highlighted slot; returns false when nothing is highlighted.
  @discardableResult
  func chooseHovered() -> Bool {
    guard let slot = hoveredSlot else { return false }
    onChoose(slot)
    return true
  }
}
