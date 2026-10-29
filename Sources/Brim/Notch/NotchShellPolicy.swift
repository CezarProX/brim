import CoreGraphics
import Foundation

// Pure decisions behind the island shell: timing, visibility, fullscreen detection, size tuning
// and swipe handling. Nothing here touches AppKit state, so every rule is unit-tested.

/// How long the pointer must rest on, or stay away from, the island.
struct ShellTiming: Equatable {
    var opensOnHover = true
    var openDelay: TimeInterval = 0.25
    var autoCollapse = true
    var collapseDelay: TimeInterval = 0.10

    static func current(_ settings: AppSettings = .shared) -> ShellTiming {
        ShellTiming(opensOnHover: settings.shellOpensOnHover, openDelay: settings.shellOpenDelay,
                    autoCollapse: settings.shellAutoCollapse, collapseDelay: settings.shellCollapseDelay)
    }
}

/// Size and position tweaks, in points, applied on top of the measured geometry.
struct ShellTuning: Equatable {
    var islandWidth: CGFloat = 0
    var islandHeight: CGFloat = 0
    var islandPosition: CGFloat = 0
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    /// Open-island scale (Regular 1, Enlarged larger).
    var openScale: CGFloat = 1
    var showsNavigation = true
    /// Widgets pinned beside the navigation capsule.
    var favorites: [IslandWidgetTile] = []

    static func current(_ settings: AppSettings = .shared) -> ShellTuning {
        ShellTuning(islandWidth: settings.shellIslandWidthOffset, islandHeight: settings.shellIslandHeightOffset,
                    islandPosition: settings.shellIslandVerticalOffset, notchWidth: settings.shellNotchWidthOffset,
                    notchHeight: settings.shellNotchHeightOffset, openScale: settings.shellOpenSize.scale,
                    showsNavigation: settings.shellShowNavigation,
                    favorites: IslandFavorites.tiles(from: settings.shellPinnedFavorites))
    }
}

enum ShellVisibility: Equatable {
    /// Drawn and interactive.
    case visible
    /// Not drawn while idle, but hovering still brings it up (External displays: "When active").
    case idle
    /// Suppressed completely: no drawing, no hover.
    case hidden
}

struct ShellVisibilityContext {
    var isExternalDisplay = false
    var externalMode: ShellExternalVisibility = .always
    var hasLiveActivity = false
    var hideOnFullscreen = true
    var displayHasFullscreenWindow = false
    var hideInMissionControl = true
    var missionControlActive = false
    var hiddenAppBundleIDs: Set<String> = []
    var frontmostBundleID: String?
    var hiddenUntil: TimeInterval?
    var now: TimeInterval = 0
    /// The island was opened on purpose and is still open: fullscreen, Mission Control and hidden
    /// apps don't hide it until it closes.
    var summoned = false
    /// This display is switched off in Settings > Island > Displays.
    var displayDisabled = false
}

enum ShellVisibilityPolicy {
    static func decide(_ context: ShellVisibilityContext) -> ShellVisibility {
        if context.displayDisabled { return .hidden }
        if context.summoned { return .visible }
        if let until = context.hiddenUntil, context.now < until { return .hidden }
        if context.hideOnFullscreen && context.displayHasFullscreenWindow { return .hidden }
        if context.hideInMissionControl && context.missionControlActive { return .hidden }
        if let front = context.frontmostBundleID, context.hiddenAppBundleIDs.contains(front) { return .hidden }
        guard context.isExternalDisplay else { return .visible }
        switch context.externalMode {
        case .never: return .hidden
        case .always: return .visible
        case .whenActive: return context.hasLiveActivity ? .visible : .idle
        }
    }
}

/// One on-screen window, as reported by the window server.
struct ShellWindowSample: Equatable {
    var pid: Int32
    var layer: Int
    var bounds: CGRect
}

enum FullscreenDetector {
    /// True when an ordinary window of another app spans the display. `bounds` use the window
    /// server's top-left origin. On notched Macs a fullscreen window may start below the camera
    /// housing, which only counts once the menu bar itself has slid away.
    static func isCovered(display: CGRect, notchHeight: CGFloat, menuBarVisible: Bool,
                          windows: [ShellWindowSample], ignoringPID: Int32) -> Bool {
        let slack: CGFloat = menuBarVisible ? 1 : notchHeight + 1
        return windows.contains { window in
            window.layer == 0 && window.pid != ignoringPID
                && abs(window.bounds.width - display.width) <= 1
                && abs(window.bounds.maxY - display.maxY) <= 1
                && abs(window.bounds.midX - display.midX) <= 1
                && window.bounds.minY - display.minY <= slack
        }
    }

    /// Mission Control draws Dock-owned windows over the whole display; the Dock has none otherwise.
    static func isMissionControl(display: CGRect, dockWindows: [CGRect]) -> Bool {
        dockWindows.contains { abs($0.width - display.width) <= 1 && abs($0.height - display.height) <= 1 }
    }
}

/// Order of the pages a horizontal swipe walks through.
enum IslandPageOrder {
    /// The tabs in order. The Tray's shows only while it holds files, or while it is the open page
    /// (a drop opens it), so the bar stays Home, Clipboard, Widgets most of the time. Messages works
    /// the same way: it shows while the inbox holds chats, or while it is the open page.
    static func visible(trayCount: Int, current: IslandPage, messageCount: Int = 0) -> [IslandPage] {
        IslandPage.allCases.filter { page in
            switch page {
            case .tray: trayCount > 0 || current == .tray
            case .messages: messageCount > 0 || current == .messages
            default: true
            }
        }
    }

    /// The page `delta` steps away, or nil past either end (the swipe rubber-bands instead).
    static func page(from current: IslandPage, delta: Int, in pages: [IslandPage]) -> IslandPage? {
        let index = pages.firstIndex(of: current) ?? 0
        let next = index + delta
        return pages.indices.contains(next) ? pages[next] : nil
    }
}

/// Turns a two-finger scroll gesture into a rubber-banded drag and a final page step.
struct SwipeTracker {
    enum Phase { case began, changed, ended }
    enum Outcome: Equatable { case none, dragging(offset: CGFloat), commit(delta: Int), cancelled }

    static let defaultCommitDistance: CGFloat = 70
    static let maxStretch: CGFloat = 46

    /// Travel needed before letting go counts as a page step (a closed-island flick uses less).
    var commitDistance = SwipeTracker.defaultCommitDistance

    init(commitDistance: CGFloat = SwipeTracker.defaultCommitDistance) { self.commitDistance = commitDistance }

    private var travel: CGFloat = 0
    private var isHorizontal = false
    private var decided = false

    /// Content follows the fingers with growing resistance, never past `maxStretch`.
    static func rubberBand(_ distance: CGFloat) -> CGFloat {
        let sign: CGFloat = distance < 0 ? -1 : 1
        let magnitude = abs(distance)
        return sign * maxStretch * (1 - 1 / (magnitude / maxStretch + 1))
    }

    /// `dx`/`dy` are the event's scrolling deltas. Swiping left (negative dx) goes to the next page.
    mutating func feed(dx: CGFloat, dy: CGFloat, phase: Phase) -> Outcome {
        switch phase {
        case .began:
            self = SwipeTracker(commitDistance: commitDistance)
            return accumulate(dx: dx, dy: dy)
        case .changed:
            return accumulate(dx: dx, dy: dy)
        case .ended:
            defer { self = SwipeTracker(commitDistance: commitDistance) }
            guard isHorizontal else { return .none }
            guard abs(travel) >= commitDistance else { return .cancelled }
            return .commit(delta: travel < 0 ? 1 : -1)
        }
    }

    private mutating func accumulate(dx: CGFloat, dy: CGFloat) -> Outcome {
        if !decided, abs(dx) + abs(dy) > 0.5 {
            decided = true
            isHorizontal = abs(dx) > abs(dy)
        }
        guard isHorizontal else { return .none }
        travel += dx
        return .dragging(offset: Self.rubberBand(travel))
    }
}
