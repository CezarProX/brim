import CoreGraphics
import Foundation

/// Pure rules for the floating Liquid Player: its three sizes, how a two-finger vertical swipe
/// morphs between them, where the window may sit, and when a drag pops the notch player out.
enum LiquidPlayerPolicy {
    /// Width is shared by Player and Expanded; Mini is a slimmer capsule.
    static func size(for kind: LiquidPlayerSize) -> CGSize {
        switch kind {
        case .mini: return CGSize(width: 300, height: 58)
        case .player: return CGSize(width: 340, height: 172)
        case .expanded: return CGSize(width: 340, height: 520)
        }
    }

    static var minHeight: CGFloat { size(for: .mini).height }
    static var maxHeight: CGFloat { size(for: .expanded).height }

    /// Fingers moving up make the player taller; natural scrolling reports that as a negative delta.
    static let scrollSensitivity: CGFloat = 1.0

    /// Height after a scroll step, clamped to the Mini...Expanded range.
    static func height(afterScrollDeltaY delta: CGFloat, from height: CGFloat) -> CGFloat {
        guard delta.isFinite, height.isFinite else { return clamp(height) }
        return clamp(height - delta * scrollSensitivity)
    }

    static func clamp(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return size(for: .player).height }
        return min(maxHeight, max(minHeight, height))
    }

    /// Continuous width that follows the height, so Mini -> Player widens as it grows.
    static func width(forHeight height: CGFloat) -> CGFloat {
        let mini = size(for: .mini), player = size(for: .player)
        let t = min(1, max(0, (clamp(height) - mini.height) / (player.height - mini.height)))
        return mini.width + (player.width - mini.width) * t
    }

    /// The size to settle on when the gesture ends: nearest, nudged by the last motion direction.
    static func snap(height: CGFloat, velocity: CGFloat = 0) -> LiquidPlayerSize {
        let nudged = clamp(height) + (velocity.isFinite ? velocity : 0) * 0.12
        return LiquidPlayerSize.allCases.min { abs(size(for: $0).height - nudged) < abs(size(for: $1).height - nudged) } ?? .player
    }

    /// Clicking the surface steps to the next size and wraps from Expanded back to Mini.
    static func next(_ kind: LiquidPlayerSize) -> LiquidPlayerSize {
        switch kind {
        case .mini: return .player
        case .player: return .expanded
        case .expanded: return .mini
        }
    }

    /// One size up or down (a mouse-wheel notch); stops at the ends.
    static func stepped(_ kind: LiquidPlayerSize, larger: Bool) -> LiquidPlayerSize {
        let all = LiquidPlayerSize.allCases
        let index = all.firstIndex(of: kind) ?? 1
        return all[min(all.count - 1, max(0, index + (larger ? 1 : -1)))]
    }

    /// Which layout to draw while the height is between sizes.
    static func layout(forHeight height: CGFloat) -> LiquidPlayerSize {
        let value = clamp(height)
        let mid1 = (size(for: .mini).height + size(for: .player).height) / 2
        let mid2 = (size(for: .player).height + size(for: .expanded).height) / 2
        return value < mid1 ? .mini : (value < mid2 ? .player : .expanded)
    }

    /// A window with its top-left at `topLeft` (screen coordinates, y up), kept inside `bounds`.
    /// A tall window near the bottom edge grows upward instead of leaving the screen.
    static func frame(topLeft: CGPoint, size: CGSize, in bounds: CGRect) -> CGRect {
        let width = min(size.width, bounds.width), height = min(size.height, bounds.height)
        let x = min(max(topLeft.x, bounds.minX), bounds.maxX - width)
        let top = min(topLeft.y, bounds.maxY)
        let y = max(top - height, bounds.minY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// A drag that starts on the notch player pops it out once it is clearly a downward pull.
    static func shouldPopOut(translation: CGSize, enabled: Bool) -> Bool {
        guard enabled, translation.width.isFinite, translation.height.isFinite else { return false }
        return translation.height >= 36 && translation.height > abs(translation.width) * 1.2
    }

    /// Where the window lands when popped out: its top edge under the pointer, near the notch.
    static func popOutTopLeft(pointer: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: pointer.x - size.width / 2, y: pointer.y + 24)
    }
}
