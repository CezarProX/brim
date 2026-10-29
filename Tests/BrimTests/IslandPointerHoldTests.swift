import CoreGraphics
import Testing
@testable import Brim

struct IslandPointerHoldTests {
  private let tall = IslandReach(shell: CGRect(x: 0, y: 600, width: 500, height: 400), tabs: nil, top: 1000)
  private let short = IslandReach(shell: CGRect(x: 0, y: 850, width: 500, height: 150), tabs: nil, top: 1000)

  /// Clipboard → Player shrinks the island and leaves the pointer far below the new tabs.
  @Test func shrinkingAwayFromThePointerKeepsItHeldWhileItMoves() {
    var hold = IslandPointerHold()
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 640), inside: true, expanded: true, reach: tall); #expect(held) }
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 640), inside: false, expanded: true, reach: short); #expect(held) }
    // Moving well past the still-pointer tolerance, inside where the island used to be.
    do { let held = hold.update(pointer: CGPoint(x: 300, y: 700), inside: false, expanded: true, reach: short); #expect(held) }
    do { let held = hold.update(pointer: CGPoint(x: 260, y: 800), inside: false, expanded: true, reach: short); #expect(held) }
  }

  @Test func leavingTheOldReachReleasesTheHold() {
    var hold = IslandPointerHold()
    _ = hold.update(pointer: CGPoint(x: 250, y: 640), inside: true, expanded: true, reach: tall)
    _ = hold.update(pointer: CGPoint(x: 250, y: 640), inside: false, expanded: true, reach: short)
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 500), inside: false, expanded: true, reach: short); #expect(!held) }
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 640), inside: false, expanded: true, reach: short); #expect(!held) }
  }

  @Test func reenteringTheIslandEndsTheHold() {
    var hold = IslandPointerHold()
    _ = hold.update(pointer: CGPoint(x: 250, y: 640), inside: true, expanded: true, reach: tall)
    _ = hold.update(pointer: CGPoint(x: 250, y: 640), inside: false, expanded: true, reach: short)
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 900), inside: true, expanded: true, reach: short); #expect(held) }
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 640), inside: false, expanded: true, reach: short); #expect(!held) }
  }

  @Test func leavingWithoutAResizeIsAStillALeave() {
    var hold = IslandPointerHold()
    _ = hold.update(pointer: CGPoint(x: 250, y: 640), inside: true, expanded: true, reach: tall)
    do { let held = hold.update(pointer: CGPoint(x: 250, y: 560), inside: false, expanded: true, reach: tall); #expect(!held) }
  }
}
