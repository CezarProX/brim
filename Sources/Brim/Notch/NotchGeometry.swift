import Foundation

enum MusicPlayerLayout {
    static let width: CGFloat = 600
    static let height: CGFloat = 264
    static let drawerHeight: CGFloat = 190
}

/// The detached navigation capsule that floats beneath the expanded island.
enum IslandNavigationLayout {
    static let height: CGFloat = 38
    static let gap: CGFloat = 12
    static let width: CGFloat = 228
    /// Padding around the three page buttons, and each button's size.
    static let inset: CGFloat = 4
    static let item: CGFloat = 30
    /// Room kept free under the capsule so its shadow is never clipped by the window.
    static let shadowMargin: CGFloat = 10
    static var reserved: CGFloat { height + gap + shadowMargin }
    /// The tallest page the open island shows under the camera band (the clipboard, Transform).
    /// The window is sized for it so the capsule under a tall page is never cut off.
    static let maxPageHeight: CGFloat = 410
}

struct NotchGeometry {
    /// Fallback dimensions used to carry the notch treatment onto displays
    /// without a physical camera cutout.
    static let simulatedNotchWidth: CGFloat = 184
    static let simulatedNotchHeight: CGFloat = 32
    /// The compact row's outer padding and glyph size (NotchShelfView.compactContent uses both).
    static let compactPadding: CGFloat = 14
    static let compactGlyph: CGFloat = 25
    /// Gap kept between a glyph and the camera housing, which hides anything under it.
    static let hardwareClearance: CGFloat = 5
    /// One compact wing beside the camera.
    static var compactWingMinimum: CGFloat { compactPadding + compactGlyph + hardwareClearance }

    /// Room the right wing's content needs: a waveform, a short value ("43.7k", "80%") or a flash readout.
    static func compactTrailingWidth(for activity: IslandActivity?) -> CGFloat {
        switch activity {
        case .recording: 0
        case nil, .music, .call: 23
        case .system: 56
        case .dictation: DictationCompactTrailing.width
        default: 44
        }
    }

    /// On the pill, music and calls draw at the two ends (artwork left, waveform right) and the
    /// recording dot keeps the leading end, like the system's own indicator; every other activity is
    /// one centred group.
    static func pillSplitsEnds(_ activity: IslandActivity?) -> Bool {
        activity == nil || activity == .music || activity == .call || activity == .recording
    }

    /// Dynamic Island style: a closed pill 150pt wide hanging just below the top edge.
    static let islandClosedWidth: CGFloat = 150
    static let islandHeight: CGFloat = 37
    static let islandTopInset: CGFloat = 4

    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var topInset: CGFloat = 0
    /// User size and position tweaks (Settings > Island > Size).
    var tuning = ShellTuning()
    var isSimulatedNotch = false
    var hasLiveActivity = false
    /// A bubble hangs off the island's right (trailing) side.
    var hasSecondaryActivity = false
    /// A bubble hangs off the island's left (leading) side, mirroring the trailing one.
    var hasLeadingBubble = false
    var audioDrawerExpanded = false
    var compactMusicLayout = false
    var compactActivity: IslandActivity?
    var compactStatusLayout = false
    var secondaryActivity: IslandActivity?
    var utilityContentHeight: CGFloat?
    /// Width chosen by the content itself, such as a shelf of Home widgets.
    var preferredWidth: CGFloat?
    var musicSummaryHeight: CGFloat = 0
    /// What the closed island shows; drives its size (HUD strip/card, notification wings, glance wings).
    var route: CompactRoute = .idle
    /// The pointer rests on the HUD: the strip grows into its card.
    var hudHovered = false
    var hudPlacement: HUDPlacement = .besideNotch
    /// Width reserved for the left/right glance when the island is idle.
    var glanceLeft: CGFloat = 0
    var glanceRight: CGFloat = 0
    /// Width of the track title shown next to the compact artwork (0 = none).
    var compactTitleWidth: CGFloat = 0
    /// Width of what a compact notification prints beside its icon (sender and "+N" badge).
    var compactLabelWidth: CGFloat = 0
    /// Height of the open notification card body (nil = the island is not showing one).
    var notificationBodyHeight: CGFloat?
    /// The capsule's measured width; nil until it has been laid out.
    var navigationWidth: CGFloat?
    /// Settings > Island > Open size: 1 regular, larger when enlarged.
    var openScale: CGFloat { tuning.openScale }
    /// False when the navigation capsule is turned off (pages change by swipe only).
    var showsNavigation: Bool { tuning.showsNavigation }

    static let notificationCardWidth: CGFloat = 372
    static let notificationWing: CGFloat = 104
    /// The pill has no camera housing; the HUD keeps a small gap between its two wings instead.
    static let floatingHUDGap: CGFloat = 56
    /// Padding plus clearance a glance wing adds around its content.
    static let glanceWingPadding: CGFloat = NotchGeometry.compactPadding + NotchGeometry.hardwareClearance

    var isFloating: Bool { notchHeight <= 0 }

    /// Keep unscaled hardware clearance above the entire music surface, including navigation.
    var musicTopInset: CGFloat { max(0, notchHeight - topInset) }

    var collapsedMainOffset: CGFloat {
        // The pill and its bubbles are centred as one group; the camera keeps the notch where it is.
        if isFloating { return (bubbleRoom(.leading) - bubbleRoom(.trailing)) / 2 }
        // Uneven wings grow away from the housing, so the camera stays under the shape's notch.
        return (wingExtras.right - wingExtras.left) / 2
    }

    /// Extra width beyond the standard wings, per side, on a notched display.
    var wingExtras: (left: CGFloat, right: CGFloat) {
        guard !isFloating else { return (0, 0) }
        switch route {
        case .idle:
            return (glanceLeft > 0 ? glanceLeft + Self.glanceWingPadding : 0,
                    glanceRight > 0 ? glanceRight + Self.glanceWingPadding : 0)
        case .activity(.music): return (compactTitleWidth > 0 ? compactTitleWidth + 6 : 0, 0)
        default: return (0, 0)
        }
    }

    var hudMetrics: HUDMetrics {
        isFloating
            ? HUDMetrics(notchWidth: Self.floatingHUDGap, closedHeight: max(24, Self.islandHeight + tuning.islandHeight),
                         floating: true)
            : HUDMetrics(notchWidth: max(60, notchWidth), closedHeight: max(12, notchHeight + tuning.notchHeight))
    }

    /// The strip hangs under the camera instead of beside it.
    var hudBelowNotch: Bool { !isFloating && hudPlacement == .belowNotch }

    /// The notch shape's bottom edge is inset by its shoulder, so HUD content gets that much extra
    /// width on each side and never touches the curve.
    var hudShoulder: CGFloat { isFloating ? 0 : min(10, max(8, (0.24 * hudMetrics.closedHeight).rounded())) }

    /// How far the closed notch shape's side edges sit inside its frame (`NotchSurfaceShape`'s
    /// shoulder). Activity rows and notifications pad their wings by it so nothing touches the curve.
    var closedShoulder: CGFloat { isFloating ? 0 : min(10, max(8, (0.24 * notchHeight).rounded())) }

    var hudSize: CGSize? {
        guard case .hud(let flash) = route else { return nil }
        let metrics = hudMetrics
        let base = hudBelowNotch && !hudHovered
            ? CGSize(width: metrics.belowStripWidth(for: flash), height: metrics.closedHeight * 2)
            : metrics.size(for: flash, expanded: hudHovered)
        return CGSize(width: base.width + 2 * hudShoulder, height: base.height)
    }

    var collapsedSize: CGSize {
        if let hudSize { return hudSize }
        if route == .notification {
            let height = isFloating ? max(24, Self.islandHeight + tuning.islandHeight) : max(12, notchHeight + tuning.notchHeight)
            // Sized to the sender: an icon and a name centred together on the pill, one per wing on a notch.
            // (Before the sender is measured, the classic 104pt wings / 250pt pill.)
            let measured = compactLabelWidth > 0
            let wing = measured
                ? closedShoulder + max(HUDMetrics.wing, CompactLayout.wing(content: compactLabelWidth)) : Self.notificationWing
            let width = isFloating
                ? (measured ? max(Self.islandClosedWidth, CompactLayout.pillWidth(content: compactLabelWidth)) : 250)
                : max(148, notchWidth) + 2 * wing
            return CGSize(width: max(60, width + (isFloating ? tuning.islandWidth : tuning.notchWidth)), height: height)
        }
        if isFloating {
            // Music and calls keep the artwork and waveform at the two ends; every other activity is
            // one centred glyph + value group, so the pill is only as wide as that group needs.
            let grouped = hasLiveActivity && !Self.pillSplitsEnds(compactActivity)
                && compactActivity != .recording
            var width: CGFloat = !hasLiveActivity ? Self.islandClosedWidth
                : grouped ? max(Self.islandClosedWidth, CompactLayout.pillWidth(content: Self.compactTrailingWidth(for: compactActivity)))
                : hasBubble || compactActivity == .recording ? 164 : 230
            if route == .activity(.music), compactTitleWidth > 0, !hasBubble { width += compactTitleWidth - 20 }
            return CGSize(width: max(60, width + tuning.islandWidth),
                          height: max(24, Self.islandHeight + tuning.islandHeight))
        }
        // Each wing holds its glyph clear of the housing; the timer's readout needs its own wider wings.
        let extras = wingExtras.left + wingExtras.right
        // Both wings equal, each: shoulder + outer inset + content + gap to the housing.
        let wings = { (content: CGFloat) in 2 * (self.closedShoulder + CompactLayout.wing(content: content)) }
        let extensionWidth: CGFloat = !hasLiveActivity ? extras
            : compactActivity == .timer ? max(132, wings(46))
            : max(wings(Self.compactGlyph), compactActivity == .recording ? 0
                : max(100, wings(Self.compactTrailingWidth(for: compactActivity)))) + extras
        return CGSize(width: max(60, max(148, notchWidth) + extensionWidth + tuning.notchWidth),
                      height: max(12, notchHeight + tuning.notchHeight))
    }

    /// The open size scaled by Settings > Open size, never wider than the display. Notifications keep their size.
    var expandedSize: CGSize {
        let natural = naturalExpandedSize
        let scale = effectiveOpenScale
        return scale == 1 ? natural : CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// The factor content is drawn at inside the open shell.
    var effectiveOpenScale: CGFloat {
        guard notificationBodyHeight == nil, openScale != 1 else { return 1 }
        let natural = naturalExpandedSize
        guard natural.width > 0 else { return 1 }
        return max(1, min(openScale, availableOpenWidth / natural.width))
    }

    /// Scaling must leave the same room for companions as the unscaled layout.
    private var availableOpenWidth: CGFloat {
        max(0, screenFrame.width - 24 - (hasBubble ? 2 * (secondarySize.width + Self.bubbleGap) : 0))
    }

    /// The open size before scaling: the layout the content is built for.
    var naturalExpandedSize: CGSize {
        if let body = notificationBodyHeight {
            let width = min(Self.notificationCardWidth + (isFloating ? 16 : 24), max(0, screenFrame.width - 24))
            return CGSize(width: width, height: max(notchHeight, 12) + body)
        }
        let natural: CGFloat = compactMusicLayout || compactStatusLayout ? 420
            : utilityContentHeight != nil ? min(740, preferredWidth ?? 480) : 600
        // The open island stays centred, so a bubble on either side needs its room on both.
        let width = min(natural, availableOpenWidth)
        let height: CGFloat = compactMusicLayout
            ? musicTopInset + (MusicPlayerLayout.height + (audioDrawerExpanded ? MusicPlayerLayout.drawerHeight : 0)) * width / MusicPlayerLayout.width + musicSummaryHeight
            : compactStatusLayout ? max(notchHeight, 12) + 142
            : max(notchHeight, 12) + min(IslandNavigationLayout.maxPageHeight, utilityContentHeight ?? 340)
        return CGSize(width: width, height: height)
    }

    var panelFrame: CGRect {
        CGRect(x: screenFrame.midX - expandedSize.width / 2, y: screenFrame.maxY - topInset - expandedSize.height,
               width: expandedSize.width, height: expandedSize.height)
    }

    /// A stable window avoids running AppKit resizing and SwiftUI layout animations together.
    /// Hover still uses panelFrame, which describes only the visible expanded shell.
    var hostingFrame: CGRect {
        let scale = max(1, openScale)
        // Reserve both companion circles even before they appear, so activity changes do not
        // resize the native window or clip bubbles beside a wide/enlarged Home shelf.
        let companionRoom = 2 * (secondarySize.width + Self.bubbleGap)
        let width = max(0, min(740 * scale + companionRoom, screenFrame.width - 24))
        let musicWidth = max(0, min(420, screenFrame.width - 24))
        let body = max(max(notchHeight, 12) + IslandNavigationLayout.maxPageHeight,
                       musicTopInset + (MusicPlayerLayout.height + MusicPlayerLayout.drawerHeight) * musicWidth / MusicPlayerLayout.width + max(48, musicSummaryHeight))
        let height = body * scale + IslandNavigationLayout.reserved
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - topInset - height,
                      width: width, height: height)
    }

    /// Where a file drag opens the notch: a generous band under the hardware.
    var dropZone: CGRect {
        let width = max(collapsedSize.width + 160, 380)
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - topInset - 110,
                      width: width, height: 110 + topInset)
    }

    /// The navigation capsule, centered a small gap below the visible shell.
    var navigationFrame: CGRect {
        let width = min(navigationWidth ?? IslandNavigationLayout.width, max(0, screenFrame.width - 24))
        return CGRect(x: screenFrame.midX - width / 2,
                      y: panelFrame.minY - IslandNavigationLayout.gap - IslandNavigationLayout.height,
                      width: width, height: IslandNavigationLayout.height)
    }

    var triggerFrame: CGRect {
        return CGRect(x: screenFrame.midX - collapsedSize.width / 2 + collapsedMainOffset,
                      y: screenFrame.maxY - topInset - collapsedSize.height,
                      width: collapsedSize.width, height: collapsedSize.height)
    }

    static let bubbleDiameter: CGFloat = 37
    static let bubbleGap: CGFloat = 7
    /// Room around the navigation capsule that still counts as the island, so a pointer
    /// overshooting a tab by a few points doesn't close it.
    static let capsuleSlack: CGFloat = 8
    /// How far the pointer may drift past an open island (under the tabs, off a corner) before it
    /// counts as leaving. Hover only: this space still lets clicks through.
    static let exitMargin: CGFloat = 24

    /// A secondary display has no hardware cutout, but the shelf still uses
    /// the attached notch presentation so it does not turn into a floating
    /// Dynamic Island capsule.
    static func simulatedExternal(screenFrame: CGRect, tuning: ShellTuning = ShellTuning()) -> NotchGeometry {
        var geometry = NotchGeometry(screenFrame: screenFrame,
                                     notchWidth: simulatedNotchWidth,
                                     notchHeight: simulatedNotchHeight,
                                     topInset: 0)
        geometry.isSimulatedNotch = true
        geometry.tuning = tuning
        return geometry
    }

    /// A floating pill below the top edge, for displays without a camera cutout.
    static func dynamicIsland(screenFrame: CGRect, tuning: ShellTuning = ShellTuning()) -> NotchGeometry {
        var geometry = NotchGeometry(screenFrame: screenFrame, notchWidth: 0, notchHeight: 0,
                                     topInset: max(0, islandTopInset + tuning.islandPosition))
        geometry.tuning = tuning
        return geometry
    }

    /// The geometry for one display: the measured hardware notch, or the chosen style for a notchless one.
    static func make(screenFrame: CGRect, hardwareNotch: (width: CGFloat, height: CGFloat)?,
                     style: ShellDisplayStyle, tuning: ShellTuning) -> NotchGeometry {
        if let hardwareNotch {
            var geometry = NotchGeometry(screenFrame: screenFrame, notchWidth: hardwareNotch.width,
                                         notchHeight: hardwareNotch.height, topInset: 0)
            geometry.tuning = tuning
            return geometry
        }
        return style == .island ? dynamicIsland(screenFrame: screenFrame, tuning: tuning)
            : simulatedExternal(screenFrame: screenFrame, tuning: tuning)
    }

    /// Either bubble is showing.
    var hasBubble: Bool { hasSecondaryActivity || hasLeadingBubble }

    func hasBubble(_ side: IslandBubbleSide) -> Bool {
        side == .leading ? hasLeadingBubble : hasSecondaryActivity
    }

    /// Width a bubble and its gap add on one side (0 when that side has none).
    func bubbleRoom(_ side: IslandBubbleSide) -> CGFloat {
        hasBubble(side) ? secondarySize.width + Self.bubbleGap : 0
    }

    /// A bubble is a circle as tall as the closed island (iPhone's minimal presentation).
    var secondarySize: CGSize {
        let height = isFloating ? max(24, Self.bubbleDiameter + tuning.islandHeight) : max(12, notchHeight + tuning.notchHeight)
        return CGSize(width: height, height: height)
    }

    /// The trailing (right) bubble.
    func secondaryFrame(expanded: Bool) -> CGRect { bubbleFrame(.trailing, expanded: expanded) }

    /// A bubble `bubbleGap` outside the island's edge on `side`, top-aligned with it; the two
    /// sides mirror each other about the island.
    func bubbleFrame(_ side: IslandBubbleSide, expanded: Bool) -> CGRect {
        let main = expanded ? panelFrame : triggerFrame
        let x = side == .trailing ? main.maxX + Self.bubbleGap : main.minX - Self.bubbleGap - secondarySize.width
        return CGRect(x: x, y: screenFrame.maxY - topInset - secondarySize.height,
                      width: secondarySize.width, height: secondarySize.height)
    }

    /// Which shown bubble a point falls on (its circle's square, up to the display's top edge).
    func bubble(at point: CGPoint, expanded: Bool) -> IslandBubbleSide? {
        IslandBubbleSide.allCases.first { side in
            guard hasBubble(side) else { return false }
            let frame = bubbleFrame(side, expanded: expanded)
            return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= screenFrame.maxY
        }
    }

    /// AppKit pointer coordinates can lie exactly on a display's upper edge.
    /// CGRect.contains excludes maxY, which made pushing against that edge miss the notch.
    func containsPointer(_ point: CGPoint, expanded: Bool) -> Bool {
        let target = expanded ? panelFrame : triggerFrame
        if point.x >= target.minX && point.x <= target.maxX
            && point.y >= target.minY && point.y <= screenFrame.maxY { return true }
        // The capsule and the gap above it, so a move from the shell to a tab never reads as leaving.
        // The gap spans the shell's whole width: a pointer heading for a tab cuts diagonally from
        // anywhere along the bottom edge, not only straight down from above the capsule.
        if expanded && showsNavigation {
            let capsule = navigationFrame.insetBy(dx: -Self.capsuleSlack, dy: -Self.capsuleSlack)
            if point.x >= target.minX && point.x <= target.maxX
                && point.y >= capsule.maxY && point.y <= target.minY { return true }
            if point.x >= capsule.minX && point.x <= capsule.maxX
                && point.y >= capsule.minY && point.y <= target.minY { return true }
        }
        // Each bubble and the gap between it and the island, so moving across never reads as leaving.
        return IslandBubbleSide.allCases.contains { side in
            guard hasBubble(side) else { return false }
            let bubble = bubbleFrame(side, expanded: expanded)
            let span = side == .trailing ? target.maxX...bubble.maxX : bubble.minX...target.minX
            return span.contains(point.x) && point.y >= bubble.minY && point.y <= max(bubble.maxY, screenFrame.maxY)
        }
    }

    /// The open island's hover reach: its shell and tabs grown by `exitMargin`.
    var openReach: IslandReach {
        let margin = Self.exitMargin
        return IslandReach(shell: panelFrame.insetBy(dx: -margin, dy: -margin),
                           tabs: showsNavigation ? navigationFrame.insetBy(dx: -margin, dy: -margin) : nil,
                           top: screenFrame.maxY)
    }

    /// Whether a pointer here keeps an open island open.
    func keepsOpen(_ point: CGPoint) -> Bool {
        containsPointer(point, expanded: true) || openReach.contains(point)
    }
}

/// Where an open island still answers hover. Rects reach up to the display's top edge, which
/// `CGRect.contains` would exclude.
struct IslandReach: Equatable {
    var shell: CGRect
    var tabs: CGRect?
    var top: CGFloat

    func contains(_ point: CGPoint) -> Bool {
        [shell, tabs].compactMap { $0 }.contains { rect in
            point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= max(rect.maxY, top)
        }
    }
}

struct ShelfHoverState {
    private(set) var isExpanded = false
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?

    mutating func reset() { self = ShelfHoverState() }

    /// A click or shortcut opened the island: it now closes the way a hover-opened one does.
    mutating func forceOpen() {
        isExpanded = true
        enteredAt = nil
        exitedAt = nil
    }

    mutating func update(isInside: Bool, isDragging: Bool, now: TimeInterval,
                         timing: ShellTiming = ShellTiming()) -> Bool {
        if isInside {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if timing.opensOnHover, now - (enteredAt ?? now) >= timing.openDelay { isExpanded = true }
        } else {
            enteredAt = nil
            if (isDragging && isExpanded) || !timing.autoCollapse {
                exitedAt = nil
            } else {
                if exitedAt == nil { exitedAt = now }
                if now - (exitedAt ?? now) >= timing.collapseDelay { isExpanded = false }
            }
        }
        return isExpanded
    }
}
