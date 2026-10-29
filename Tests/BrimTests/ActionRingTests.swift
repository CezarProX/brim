import Foundation
import Testing

@testable import Brim

struct ActionRingTests {
  @Test func angleIsClockwiseFromTwelve() {
    #expect(abs(RingGeometry.angle(dx: 0, dy: -10) - 0) < 0.001)
    #expect(abs(RingGeometry.angle(dx: 10, dy: 0) - 90) < 0.001)
    #expect(abs(RingGeometry.angle(dx: 0, dy: 10) - 180) < 0.001)
    #expect(abs(RingGeometry.angle(dx: -10, dy: 0) - 270) < 0.001)
  }

  @Test func hitTestPicksTheWedgeUnderThePointer() {
    #expect(RingGeometry.slot(dx: 0, dy: -80, count: 8) == 0)
    #expect(RingGeometry.slot(dx: 80, dy: 0, count: 8) == 2)
    #expect(RingGeometry.slot(dx: 0, dy: 80, count: 8) == 4)
    #expect(RingGeometry.slot(dx: -80, dy: 0, count: 8) == 6)
    // 20 degrees clockwise of 12 o'clock is still slot 0 (wedges are 45 degrees wide, centered).
    #expect(RingGeometry.slot(dx: 80 * CGFloat(sin(20 * Double.pi / 180)), dy: -80 * CGFloat(cos(20 * Double.pi / 180)), count: 8) == 0)
    // 25 degrees crosses into slot 1.
    #expect(RingGeometry.slot(dx: 80 * CGFloat(sin(25 * Double.pi / 180)), dy: -80 * CGFloat(cos(25 * Double.pi / 180)), count: 8) == 1)
    // Just left of twelve wraps to slot 0, not -1.
    #expect(RingGeometry.slot(dx: -5, dy: -80, count: 8) == 0)
  }

  @Test func deadZoneSelectsNothing() {
    #expect(RingGeometry.slot(dx: 5, dy: -5, count: 8) == nil)
    #expect(RingGeometry.slot(dx: 0, dy: 0, count: 0) == nil)
  }

  @Test func highlightTurnsTheShortWay() {
    #expect(RingGeometry.unwrapped(previous: 350, target: 10) == 370)
    #expect(RingGeometry.unwrapped(previous: 10, target: 350) == -10)
    #expect(RingGeometry.unwrapped(previous: 90, target: 135) == 135)
  }

  @Test func ringNumberWrapsAround() {
    #expect(RingGeometry.ring(after: 2, step: 1, count: 3) == 0)
    #expect(RingGeometry.ring(after: 0, step: -1, count: 3) == 2)
    #expect(RingGeometry.ring(after: 0, step: 1, count: 1) == 0)
  }

  @Test func layoutNeverHasMoreThanThreeRingsOrFewerThanOne() {
    var layout = RingLayout(rings: [])
    #expect(layout.rings.count == 1)
    layout = layout.addingRing().addingRing().addingRing().addingRing()
    #expect(layout.rings.count == 3 && !layout.canAddRing)
    layout = layout.removingRing(at: 0).removingRing(at: 0).removingRing(at: 0)
    #expect(layout.rings.count == 1)
  }

  @Test func swappingMovesSlotsWithoutMutatingTheOriginal() {
    let original = RingLayout.standard
    let first = original.rings[0].slots[0]
    let swapped = original.swapping(ring: 0, from: 0, to: 5)
    #expect(swapped.rings[0].slots[5] == first)
    #expect(original.rings[0].slots[0] == first)
    #expect(swapped.rings[0].slots[0] == original.rings[0].slots[5])
  }

  @Test func copyingGivesTheCopyANewIdentity() {
    let layout = RingLayout.standard.addingRing()
    let copied = layout.copying(fromRing: 0, from: 1, toRing: 1, to: 3)
    let source = layout.rings[0].slots[1]
    let target = copied.rings[1].slots[3]
    #expect(target?.title == source?.title)
    #expect(target?.id != source?.id)
  }

  @Test func layoutRoundTripsThroughSettings() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Ring-\(UUID().uuidString)")!)
    #expect(settings.ringLayout == .standard || settings.ringLayout.rings.count == 1)
    let custom = RingLayout.standard.addingRing().setting(RingSlot(kind: .openURL, argument: "https://example.com"), ring: 1, index: 2)
    settings.ringLayout = custom
    #expect(settings.ringLayout == custom)
  }

  @Test func shortcutsRunByNameWithoutAShell() {
    #expect(RingActionPlan.shortcutArguments(name: "  My Flow; rm -rf / ") == ["run", "My Flow; rm -rf /"])
    #expect(RingActionPlan.shortcutArguments(name: "   ") == nil)
  }

  @Test func urlsAreNormalizedAndDangerousSchemesRefused() {
    #expect(RingActionPlan.openableURL("example.com")?.absoluteString == "https://example.com")
    #expect(RingActionPlan.openableURL("slack://open")?.scheme == "slack")
    #expect(RingActionPlan.openableURL("file:///etc/passwd") == nil)
    #expect(RingActionPlan.openableURL("javascript:alert(1)") == nil)
    #expect(RingActionPlan.openableURL("") == nil)
  }

  @Test func keystrokeArgumentRoundTrips() {
    let stroke = RingKeystroke(keyCode: 8, modifiers: 256 | 512, label: "C")
    let parsed = RingKeystroke(stroke.argument)
    #expect(parsed == stroke)
    #expect(stroke.display == "⇧⌘C")
    #expect(RingKeystroke("999|0|X") == nil)
    #expect(RingKeystroke("garbage") == nil)
  }

  @MainActor @Test func viewModelFollowsThePointerAndSkipsEmptySlots() {
    let layout = RingLayout.standard.setting(nil, ring: 0, index: 2)
    let model = RingViewModel(layout: layout)
    model.pointerMoved(dx: 80, dy: 0)
    #expect(model.hovered == nil)  // slot 2 is empty
    model.pointerMoved(dx: 0, dy: -80)
    #expect(model.hovered == 0)
    var chosen: RingSlot?
    model.onChoose = { chosen = $0 }
    #expect(model.chooseHovered())
    #expect(chosen?.title == "Capture")
    model.pointerLeft()
    #expect(!model.chooseHovered())
  }

  @MainActor @Test func numberKeysSwitchOnlyToExistingRings() {
    let model = RingViewModel(layout: RingLayout.standard.addingRing())
    model.selectRing(number: 3)
    #expect(model.ringIndex == 0)
    model.selectRing(number: 2)
    #expect(model.ringIndex == 1)
    model.switchRing(step: 1)
    #expect(model.ringIndex == 0)
  }

  @Test func dropPayloadsRoundTripAndReject() {
    let slot = RingDropPayload.slot(ring: 1, index: 4)
    #expect(RingDropPayload(slot.text) == slot)
    let action = RingDropPayload.action(kind: .openURL, argument: "https://a.b/c:d")
    #expect(RingDropPayload(action.text) == action)
    #expect(RingDropPayload("nonsense") == nil)
    #expect(RingDropPayload("action:bogus:x") == nil)
  }

  @Test func droppingAppliesSwapCopyOrFill() {
    let layout = RingLayout.standard.addingRing()
    let swapped = layout.applying(.slot(ring: 0, index: 0), toRing: 0, index: 7)
    #expect(swapped.rings[0].slots[7]?.title == "Capture")
    let copied = layout.applying(.slot(ring: 0, index: 0), toRing: 1, index: 0)
    #expect(copied.rings[1].slots[0]?.title == "Capture" && copied.rings[0].slots[0] != nil)
    let filled = layout.applying(.action(kind: .shortcut, argument: "Morning"), toRing: 1, index: 5)
    #expect(filled.rings[1].slots[5]?.title == "Morning" && filled.rings[1].slots[5]?.kind == .shortcut)
  }
}
