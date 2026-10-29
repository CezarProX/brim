import SwiftUI

extension View {
    /// Dragging this part of the notch player down pulls it out into the floating Liquid Player
    /// (Settings: "Dragging the notch player pops out to floating"). Scrubber and buttons are
    /// outside the handle, so seeking is never mistaken for a pop-out.
    func popOutHandle() -> some View { modifier(PopOutHandle()) }
}

/// The card leaves the notch as soon as a pull starts; from then on the controller follows the
/// pointer itself, so the drag survives the island collapsing underneath it.
private struct PopOutHandle: ViewModifier {
    @State private var began = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    guard !began, LiquidPopOutDrag.shouldBegin(translation: value.translation,
                                                               enabled: AppSettings.shared.notchPlayerDragPopsOut) else { return }
                    began = true
                    MainActor.assumeIsolated { LiquidPlayerController.shared.beginPopOutDrag(translation: value.translation) }
                }
                .onEnded { _ in began = false })
    }
}

/// Pure rules for pulling the player out of the notch: when the pull starts, how the card grows
/// and fades in with it, and where it lands when released.
enum LiquidPopOutDrag {
    /// Points of pull over which the card fades and scales in.
    static let fadeIn: CGFloat = 40
    /// The pull where the card starts growing past Player, and how much more reaches Expanded.
    static let growStart: CGFloat = 30
    static let growSpan: CGFloat = 260
    /// Released past this the card stays out; a quick flick needs only `flickPull`.
    static let commitPull: CGFloat = 56
    static let flickPull: CGFloat = 20
    static let flickVelocity: CGFloat = 600
    /// How far below the pointer the card's top edge hangs.
    static let grip: CGFloat = 16

    static func shouldBegin(translation: CGSize, enabled: Bool) -> Bool {
        guard enabled, translation.width.isFinite, translation.height.isFinite else { return false }
        return translation.height >= 8 && translation.height > abs(translation.width) * 1.1
    }

    static func height(pull: CGFloat) -> CGFloat {
        let player = LiquidPlayerPolicy.size(for: .player).height
        let expanded = LiquidPlayerPolicy.size(for: .expanded).height
        guard pull.isFinite else { return player }
        let t = min(1, max(0, (pull - growStart) / growSpan))
        let eased = 1 - (1 - t) * (1 - t)
        return player + (expanded - player) * eased
    }

    static func progress(pull: CGFloat) -> CGFloat {
        guard pull.isFinite else { return 0 }
        return min(1, max(0, pull / fadeIn))
    }

    /// `velocity` is downward points per second.
    static func commits(pull: CGFloat, velocity: CGFloat) -> Bool {
        pull >= commitPull || (pull >= flickPull && velocity >= flickVelocity)
    }

    /// Player or Expanded, whichever the card is closer to once the flick is counted; never Mini.
    static func settledSize(height: CGFloat, velocity: CGFloat) -> LiquidPlayerSize {
        let kind = LiquidPlayerPolicy.snap(height: height, velocity: velocity)
        return kind == .mini ? .player : kind
    }

    /// The card's top-left (screen coordinates, y up) hanging from the pointer.
    static func topLeft(pointer: CGPoint, width: CGFloat) -> CGPoint {
        CGPoint(x: pointer.x - width / 2, y: pointer.y + grip)
    }
}
