import CoreGraphics
import Testing
@testable import Brim

@Suite("Island scroll regions")
struct IslandScrollRegionTests {
  private func extent(offset: CGFloat, content: CGFloat = 600, viewport: CGFloat = 300) -> HorizontalScrollExtent {
    HorizontalScrollExtent(offset: offset, content: content, viewport: viewport)
  }

  private func decide(_ region: IslandSwipeGate.Region, dx: CGFloat, dy: CGFloat = 0) -> Bool {
    var gate = IslandSwipeGate()
    _ = gate.allows(dx: 0, dy: 0, phase: .began, region: { region })
    return gate.allows(dx: dx, dy: dy, phase: .changed, region: { region })
  }

  @Test func plainContentTurnsPages() {
    #expect(decide(.none, dx: -20))
  }

  @Test func scrollerInMiddleKeepsTheSwipe() {
    #expect(!decide(.scroller(extent(offset: 100)), dx: -20))
    #expect(!decide(.scroller(extent(offset: 100)), dx: 20))
  }

  @Test func scrollerAtStartKeepsForwardSwipeButYieldsBackward() {
    let atStart = IslandSwipeGate.Region.scroller(extent(offset: 0))
    #expect(!decide(atStart, dx: -20))
    #expect(decide(atStart, dx: 20))
  }

  @Test func scrollerAtEndYieldsForwardSwipe() {
    let atEnd = IslandSwipeGate.Region.scroller(extent(offset: 300))
    #expect(decide(atEnd, dx: -20))
    #expect(!decide(atEnd, dx: 20))
  }

  @Test func contentThatFitsDoesNotConsume() {
    #expect(decide(.scroller(extent(offset: 0, content: 300)), dx: -20))
  }

  @Test func blockerNeverTurnsPages() {
    #expect(!decide(.blocker, dx: -20))
    #expect(!decide(.blocker, dx: 20))
  }

  @Test func verticalGesturesAreNeverBlocked() {
    #expect(decide(.scroller(extent(offset: 100)), dx: 2, dy: 30))
  }

  @Test func decisionHoldsForTheWholeGestureAndResetsAfter() {
    var gate = IslandSwipeGate()
    let middle = IslandSwipeGate.Region.scroller(extent(offset: 100))
    _ = gate.allows(dx: 0, dy: 0, phase: .began, region: { middle })
    let first = gate.allows(dx: -10, dy: 0, phase: .changed, region: { middle })
    // Reaching the edge mid-gesture does not flip the decision.
    let second = gate.allows(dx: -10, dy: 0, phase: .changed, region: { .none })
    _ = gate.allows(dx: 0, dy: 0, phase: .ended, region: { .none })
    let next = gate.allows(dx: -10, dy: 0, phase: .began, region: { .none })
    #expect(!first && !second && next)
  }

  @Test func regionIsOnlyLookedUpOnceDirectionIsKnown() {
    var gate = IslandSwipeGate()
    var lookups = 0
    _ = gate.allows(dx: 0, dy: 0, phase: .began, region: { lookups += 1; return .none })
    #expect(lookups == 0)
    _ = gate.allows(dx: -9, dy: 0, phase: .changed, region: { lookups += 1; return .none })
    _ = gate.allows(dx: -9, dy: 0, phase: .changed, region: { lookups += 1; return .none })
    #expect(lookups == 1)
  }

  @Test func wheelMapsVerticalToHorizontal() {
    #expect(IslandWheelMapping.offsetDelta(dx: 0, dy: -1, precise: false) == IslandWheelMapping.notchPoints)
    #expect(IslandWheelMapping.offsetDelta(dx: 0, dy: 1, precise: false) == -IslandWheelMapping.notchPoints)
    #expect(IslandWheelMapping.offsetDelta(dx: 0, dy: -7, precise: true) == 7)
  }

  @Test func wheelIgnoresHorizontalAndEmptyEvents() {
    #expect(IslandWheelMapping.offsetDelta(dx: 5, dy: -1, precise: true) == nil)
    #expect(IslandWheelMapping.offsetDelta(dx: 0, dy: 0, precise: false) == nil)
  }

  @Test func offsetsClampToTheScrollableRange() {
    #expect(IslandWheelMapping.clamped(-40, content: 600, viewport: 300) == 0)
    #expect(IslandWheelMapping.clamped(900, content: 600, viewport: 300) == 300)
    #expect(IslandWheelMapping.clamped(50, content: 200, viewport: 300) == 0)
  }
}
