import Foundation

enum LockCardKind: String, CaseIterable, Equatable {
    case nowPlaying, awake, timer

    var height: CGFloat {
        switch self {
        case .nowPlaying: return 168
        case .awake: return 72
        case .timer: return 96
        }
    }
}

/// Which cards are wanted and which have something to show.
struct LockCardInputs: Equatable {
    var mediaEnabled = true
    var timerEnabled = true
    var awakeEnabled = true
    var hasMedia = false
    var timerActive = false
    var awakeActive = false
    var statusRowEnabled = true
    var statusItemCount = 0
}

/// Where the cards go. Now Playing sits on top, High Alert in the middle and the timer at
/// the bottom, anchored above the login area. Frames are in screen coordinates, origin bottom-left.
struct LockScreenLayout: Equatable {
    struct Placed: Equatable { let kind: LockCardKind; let frame: CGRect }

    static let cardWidth: CGFloat = 372
    static let spacing: CGFloat = 10
    static let statusRowHeight: CGFloat = 64
    /// Gap kept above the password field and avatar.
    static let loginClearance: CGFloat = 0.20
    static let clockClearance: CGFloat = 0.30
    static let margin: CGFloat = 16

    let cards: [Placed]
    /// nil when the row is off or has nothing to show.
    let statusRow: CGRect?
    /// The union of the cards, for sizing the card window.
    var cardsFrame: CGRect? {
        guard let first = cards.first?.frame else { return nil }
        return cards.dropFirst().reduce(first) { $0.union($1.frame) }
    }

    static func order(_ inputs: LockCardInputs) -> [LockCardKind] {
        var kinds: [LockCardKind] = []
        if inputs.mediaEnabled && inputs.hasMedia { kinds.append(.nowPlaying) }
        if inputs.awakeEnabled && inputs.awakeActive { kinds.append(.awake) }
        if inputs.timerEnabled && inputs.timerActive { kinds.append(.timer) }
        return kinds
    }

    static func plan(_ inputs: LockCardInputs, screen: CGRect, verticalOffset: CGFloat = 0) -> LockScreenLayout {
        let width = min(cardWidth, screen.width - margin * 2)
        let x = screen.midX - width / 2
        let floorY = screen.minY + screen.height * loginClearance + verticalOffset
        let ceiling = screen.maxY - screen.height * clockClearance
        let available = max(0, ceiling - floorY)

        // Bottom-up, drop the lowest-priority cards (timer first) when the screen is too short.
        var kinds = order(inputs)
        while kinds.count > 1, stackHeight(kinds) > available { kinds.removeLast() }
        if kinds.count == 1, stackHeight(kinds) > available + 40 { kinds = [] }

        var y = floorY
        var placed: [Placed] = []
        for kind in kinds.reversed() {
            placed.append(Placed(kind: kind, frame: CGRect(x: x, y: y, width: width, height: kind.height)))
            y += kind.height + spacing
        }
        let showsRow = inputs.statusRowEnabled && inputs.statusItemCount > 0
        let row = showsRow
            ? CGRect(x: x, y: screen.maxY - screen.height * clockClearance - statusRowHeight - 6,
                     width: width, height: statusRowHeight)
            : nil
        return LockScreenLayout(cards: placed.reversed(), statusRow: row)
    }

    private static func stackHeight(_ kinds: [LockCardKind]) -> CGFloat {
        kinds.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, kinds.count - 1))
    }
}

/// Whether a song should still be on the lock screen.
enum LockMediaVisibility {
    static func shouldShow(hasTrack: Bool, isPlaying: Bool, pausedFor: TimeInterval?, hideAfterMinutes: Int) -> Bool {
        guard hasTrack else { return false }
        if isPlaying { return true }
        guard let pausedFor else { return hideAfterMinutes > 0 }
        return pausedFor <= TimeInterval(hideAfterMinutes * 60)
    }
}
