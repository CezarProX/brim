import CoreGraphics

/// Tells "the pointer left the island" apart from "the island moved away from the pointer".
///
/// Clicking a page in the navigation capsule resizes the open island, which moves the capsule
/// (and the shell's bottom edge) out from under a pointer that never moved. Read naively, that is
/// the pointer leaving: the hover collapses the island a tenth of a second later and the collapse
/// resets the page to Home, so the click appears to do nothing. The same happens when a widget
/// tile opens a shorter view. While the pointer stays where it last was inside the island, the
/// island stays hovered; any real movement away releases the hold.
///
/// A big shrink (Clipboard → Player) can leave the pointer far below the new tabs, and the first
/// move toward them used to release the hold. So when the island shrinks out from under the
/// pointer, the space it covered before keeps it open until the pointer is back on the island
/// or leaves that space.
struct IslandPointerHold {
    /// How far the pointer may drift from its last inside position and still count as resting.
    static let tolerance: CGFloat = 6
    private(set) var anchor: CGPoint?
    /// The island's reach before it shrank away from the pointer.
    private(set) var heldReach: IslandReach?
    private var lastReach: IslandReach?
    private var wasInside = false

    /// - Returns: whether the hover should treat the pointer as inside the island.
    mutating func update(pointer: CGPoint, inside: Bool, expanded: Bool, reach: IslandReach? = nil) -> Bool {
        let previousReach = lastReach
        lastReach = reach
        guard expanded else {
            anchor = nil
            heldReach = nil
            wasInside = false
            return inside
        }
        wasInside = hold(pointer: pointer, inside: inside, reach: reach, previousReach: previousReach)
        return wasInside
    }

    private mutating func hold(pointer: CGPoint, inside: Bool, reach: IslandReach?, previousReach: IslandReach?) -> Bool {
        if inside {
            anchor = pointer
            heldReach = nil
            return true
        }
        if heldReach == nil, wasInside, let previousReach, previousReach != reach, previousReach.contains(pointer) {
            heldReach = previousReach
        }
        if let heldReach, heldReach.contains(pointer) { return true }
        heldReach = nil
        guard let anchor, hypot(pointer.x - anchor.x, pointer.y - anchor.y) <= Self.tolerance else {
            anchor = nil
            return false
        }
        return true
    }
}
