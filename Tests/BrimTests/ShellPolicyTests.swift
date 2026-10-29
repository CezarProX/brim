import CoreGraphics
import Foundation
import Testing

@testable import Brim

struct ShellHoverTimingTests {
    @Test func defaultsKeepTheShippedTiming() {
        var hover = ShelfHoverState()
        let r1 = hover.update(isInside: true, isDragging: false, now: 0)
        #expect(!r1)
        let r2 = hover.update(isInside: true, isDragging: false, now: 0.25)
        #expect(r2)
        let r3 = hover.update(isInside: false, isDragging: false, now: 1)
        #expect(r3)
        let r4 = hover.update(isInside: false, isDragging: false, now: 1.09)
        #expect(r4)
        let r5 = hover.update(isInside: false, isDragging: false, now: 1.10)
        #expect(!r5)
    }

    @Test func openDelayIsConfigurable() {
        var hover = ShelfHoverState()
        let timing = ShellTiming(openDelay: 0.5)
        let r6 = hover.update(isInside: true, isDragging: false, now: 0, timing: timing)
        #expect(!r6)
        let r7 = hover.update(isInside: true, isDragging: false, now: 0.49, timing: timing)
        #expect(!r7)
        let r8 = hover.update(isInside: true, isDragging: false, now: 0.5, timing: timing)
        #expect(r8)
    }

    @Test func hoverNeverOpensWhenOpeningOnHoverIsOff() {
        var hover = ShelfHoverState()
        let timing = ShellTiming(opensOnHover: false)
        for step in 0..<20 {
            let r = hover.update(isInside: true, isDragging: false, now: Double(step), timing: timing)
            #expect(!r)
        }
    }

    @Test func clickOpenedIslandStillCollapsesWhenHoverOpenIsOff() {
        var hover = ShelfHoverState()
        let timing = ShellTiming(opensOnHover: false, collapseDelay: 0.1)
        hover.forceOpen()
        let r10 = hover.update(isInside: true, isDragging: false, now: 0, timing: timing)
        #expect(r10)
        let r11 = hover.update(isInside: false, isDragging: false, now: 1, timing: timing)
        #expect(r11)
        let r12 = hover.update(isInside: false, isDragging: false, now: 1.1, timing: timing)
        #expect(!r12)
    }

    @Test func collapseDelayIsConfigurableAndAutoCollapseCanBeOff() {
        var hover = ShelfHoverState()
        hover.forceOpen()
        let slow = ShellTiming(collapseDelay: 1)
        let r13 = hover.update(isInside: false, isDragging: false, now: 0, timing: slow)
        #expect(r13)
        let r14 = hover.update(isInside: false, isDragging: false, now: 0.99, timing: slow)
        #expect(r14)
        let r15 = hover.update(isInside: false, isDragging: false, now: 1, timing: slow)
        #expect(!r15)

        hover.forceOpen()
        let sticky = ShellTiming(autoCollapse: false)
        for step in 0..<10 {
            let r = hover.update(isInside: false, isDragging: false, now: 100 + Double(step), timing: sticky)
            #expect(r)
        }
    }

    @Test func returningInsideCancelsAPendingCollapse() {
        var hover = ShelfHoverState()
        hover.forceOpen()
        let r17 = hover.update(isInside: false, isDragging: false, now: 0)
        #expect(r17)
        let r18 = hover.update(isInside: true, isDragging: false, now: 0.2)
        #expect(r18)
        let r19 = hover.update(isInside: false, isDragging: false, now: 0.3)
        #expect(r19)
        let r20 = hover.update(isInside: false, isDragging: false, now: 0.35)
        #expect(r20)
    }
}

struct ShellVisibilityPolicyTests {
    private func decide(_ edit: (inout ShellVisibilityContext) -> Void) -> ShellVisibility {
        var context = ShellVisibilityContext()
        edit(&context)
        return ShellVisibilityPolicy.decide(context)
    }

    @Test func visibleByDefault() { #expect(decide { (_: inout ShellVisibilityContext) in } == .visible) }

    /// ⌥⌘N, the clipboard hotkey and widget requests must work over a fullscreen app.
    @Test func aSummonedIslandShowsOverFullscreenButNotOnADisabledDisplay() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.displayHasFullscreenWindow = true; c.summoned = true } == .visible)
        #expect(decide { (c: inout ShellVisibilityContext) in c.missionControlActive = true; c.summoned = true } == .visible)
        #expect(decide { (c: inout ShellVisibilityContext) in c.displayDisabled = true; c.summoned = true } == .hidden)
    }

    @Test func fullscreenHidesOnlyThatDisplayAndOnlyWhenEnabled() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.displayHasFullscreenWindow = true } == .hidden)
        #expect(decide { (c: inout ShellVisibilityContext) in c.displayHasFullscreenWindow = true; c.hideOnFullscreen = false } == .visible)
    }

    @Test func missionControlHides() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.missionControlActive = true } == .hidden)
        #expect(decide { (c: inout ShellVisibilityContext) in c.missionControlActive = true; c.hideInMissionControl = false } == .visible)
    }

    @Test func hiddenAppsHideWhileFrontmost() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.hiddenAppBundleIDs = ["com.game"]; c.frontmostBundleID = "com.game" } == .hidden)
        #expect(decide { (c: inout ShellVisibilityContext) in c.hiddenAppBundleIDs = ["com.game"]; c.frontmostBundleID = "com.apple.finder" } == .visible)
        #expect(decide { (c: inout ShellVisibilityContext) in c.hiddenAppBundleIDs = ["com.game"]; c.frontmostBundleID = nil } == .visible)
    }

    @Test func manualHideExpires() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.hiddenUntil = 3600; c.now = 100 } == .hidden)
        #expect(decide { (c: inout ShellVisibilityContext) in c.hiddenUntil = 3600; c.now = 3600 } == .visible)
    }

    @Test func externalDisplayModes() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = true; c.externalMode = .never } == .hidden)
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = true; c.externalMode = .always } == .visible)
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = true; c.externalMode = .whenActive } == .idle)
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = true; c.externalMode = .whenActive; c.hasLiveActivity = true } == .visible)
        // The built-in display ignores the external setting.
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = false; c.externalMode = .never } == .visible)
    }

    @Test func suppressionBeatsExternalAlways() {
        #expect(decide { (c: inout ShellVisibilityContext) in c.isExternalDisplay = true; c.displayHasFullscreenWindow = true } == .hidden)
    }
}

struct FullscreenDetectorTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private func window(_ rect: CGRect, pid: Int32 = 10, layer: Int = 0) -> ShellWindowSample {
        ShellWindowSample(pid: pid, layer: layer, bounds: rect)
    }

    @Test func windowSpanningTheDisplayIsFullscreen() {
        #expect(FullscreenDetector.isCovered(display: display, notchHeight: 0, menuBarVisible: false,
                                             windows: [window(display)], ignoringPID: 1))
    }

    @Test func maximizedWindowBelowAVisibleMenuBarIsNot() {
        let zoomed = CGRect(x: 0, y: 33, width: 1512, height: 949)
        #expect(!FullscreenDetector.isCovered(display: display, notchHeight: 33, menuBarVisible: true,
                                              windows: [window(zoomed)], ignoringPID: 1))
    }

    @Test func fullscreenWithAnAlwaysVisibleMenuBarStillCounts() {
        #expect(FullscreenDetector.isCovered(display: display, notchHeight: 0, menuBarVisible: true,
                                             windows: [window(display)], ignoringPID: 1))
    }

    @Test func windowExtendingAboveTheDisplayIsNotFullscreenOnIt() {
        let spanning = CGRect(x: 0, y: -500, width: 1512, height: 1482)
        #expect(!FullscreenDetector.isCovered(display: display, notchHeight: 33, menuBarVisible: false,
                                              windows: [window(spanning)], ignoringPID: 1))
    }

    @Test func notchedFullscreenBelowTheCameraCountsOnceTheMenuBarIsGone() {
        let belowNotch = CGRect(x: 0, y: 33, width: 1512, height: 949)
        #expect(FullscreenDetector.isCovered(display: display, notchHeight: 33, menuBarVisible: false,
                                             windows: [window(belowNotch)], ignoringPID: 1))
    }

    @Test func ownWindowsAndOverlayLayersAreIgnored() {
        #expect(!FullscreenDetector.isCovered(display: display, notchHeight: 0, menuBarVisible: false,
                                              windows: [window(display, pid: 1)], ignoringPID: 1))
        #expect(!FullscreenDetector.isCovered(display: display, notchHeight: 0, menuBarVisible: false,
                                              windows: [window(display, layer: 25)], ignoringPID: 1))
    }

    @Test func smallWindowsAndOtherDisplaysDoNotCount() {
        let small = CGRect(x: 100, y: 100, width: 800, height: 600)
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        #expect(!FullscreenDetector.isCovered(display: display, notchHeight: 0, menuBarVisible: false,
                                              windows: [window(small), window(other)], ignoringPID: 1))
    }

    @Test func missionControlIsADisplaySizedDockWindow() {
        #expect(FullscreenDetector.isMissionControl(display: display, dockWindows: [display]))
        #expect(!FullscreenDetector.isMissionControl(display: display, dockWindows: [CGRect(x: 0, y: 900, width: 600, height: 80)]))
        #expect(!FullscreenDetector.isMissionControl(display: display, dockWindows: []))
    }
}

struct ShellGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func islandPillMatchesDesignNumbers() {
        let island = NotchGeometry.dynamicIsland(screenFrame: screen)
        #expect(island.isFloating)
        #expect(island.collapsedSize.width == 150)
        #expect(island.topInset == NotchGeometry.islandTopInset)
        #expect(island.triggerFrame.maxY == screen.maxY - NotchGeometry.islandTopInset)
        #expect(island.triggerFrame.midX == screen.midX)
    }

    @Test func islandHitTestingCoversThePillAndTheGapAboveIt() {
        let island = NotchGeometry.dynamicIsland(screenFrame: screen)
        #expect(island.containsPointer(CGPoint(x: screen.midX, y: screen.maxY), expanded: false))
        #expect(island.containsPointer(CGPoint(x: screen.midX, y: screen.maxY - 20), expanded: false))
        #expect(!island.containsPointer(CGPoint(x: screen.midX + 200, y: screen.maxY - 20), expanded: false))
        #expect(!island.containsPointer(CGPoint(x: screen.midX, y: screen.maxY - 120), expanded: false))
    }

    @Test func islandOffsetsResizeAndMoveItWhileHitTestingFollows() {
        let tuning = ShellTuning(islandWidth: 30, islandHeight: 6, islandPosition: 12)
        let island = NotchGeometry.dynamicIsland(screenFrame: screen, tuning: tuning)
        #expect(island.collapsedSize.width == 180)
        #expect(island.collapsedSize.height == 43)
        #expect(island.topInset == 16)
        #expect(island.triggerFrame.maxY == screen.maxY - 16)
        #expect(island.containsPointer(CGPoint(x: screen.midX + 85, y: screen.maxY - 26), expanded: false))
        #expect(!island.containsPointer(CGPoint(x: screen.midX + 95, y: screen.maxY - 26), expanded: false))
    }

    @Test func islandHostingCanvasStillContainsTheOpenShell() {
        for position in [-4.0, 0, 40] {
            var island = NotchGeometry.dynamicIsland(screenFrame: screen, tuning: ShellTuning(islandPosition: position))
            island.hasLiveActivity = true
            #expect(island.hostingFrame.contains(island.panelFrame))
            #expect(island.hostingFrame.maxY == screen.maxY - island.topInset)
        }
    }

    @Test func notchOffsetsOnlyChangeTheClosedSizeAndStayCentered() {
        let base = NotchGeometry.simulatedExternal(screenFrame: screen)
        let wide = NotchGeometry.simulatedExternal(screenFrame: screen, tuning: ShellTuning(notchWidth: 40, notchHeight: 4))
        #expect(wide.collapsedSize.width == base.collapsedSize.width + 40)
        #expect(wide.collapsedSize.height == base.collapsedSize.height + 4)
        #expect(wide.expandedSize == base.expandedSize)
        #expect(wide.triggerFrame.maxY == screen.maxY)
        #expect(wide.triggerFrame.midX == screen.midX)
    }

    @Test func islandOffsetsDoNotAffectTheNotch() {
        let base = NotchGeometry.simulatedExternal(screenFrame: screen)
        let tuned = NotchGeometry.simulatedExternal(screenFrame: screen, tuning: ShellTuning(islandWidth: 90, islandPosition: 30))
        #expect(tuned.collapsedSize == base.collapsedSize)
        #expect(tuned.topInset == 0)
    }

    @Test func sizesNeverCollapseToNothing() {
        let tiny = NotchGeometry.dynamicIsland(screenFrame: screen, tuning: ShellTuning(islandWidth: -500, islandHeight: -500))
        #expect(tiny.collapsedSize.width >= 60 && tiny.collapsedSize.height >= 24)
    }

    @Test func factoryPicksTheRightShapeForEachDisplay() {
        let hardware = NotchGeometry.make(screenFrame: screen, hardwareNotch: (width: 184, height: 33),
                                          style: .island, tuning: ShellTuning())
        #expect(!hardware.isFloating && !hardware.isSimulatedNotch && hardware.notchHeight == 33)
        let attached = NotchGeometry.make(screenFrame: screen, hardwareNotch: nil, style: .notch, tuning: ShellTuning())
        #expect(attached.isSimulatedNotch && !attached.isFloating)
        let pill = NotchGeometry.make(screenFrame: screen, hardwareNotch: nil, style: .island, tuning: ShellTuning())
        #expect(pill.isFloating)
    }

    @Test func activitiesWidenTheIslandPill() {
        var island = NotchGeometry.dynamicIsland(screenFrame: screen)
        island.hasLiveActivity = true
        #expect(island.collapsedSize.width > 150)
    }
}

struct ShellAnimationSpeedTests {
    @Test func presetsScaleDurationsInOrder() {
        let scales = ShellAnimationSpeed.allCases.map(\.durationScale)
        let expected: [Double] = ShellAnimationSpeed.allCases.map { 1 / $0.speedMultiplier }
        #expect(ShellAnimationSpeed.allCases.map(\.speedMultiplier) == [0.7, 1.0, 1.5, 3.0])
        #expect(scales == expected)
        #expect(scales == scales.sorted(by: >))
    }

    @Test func fasterSpeedsProduceShorterSprings() {
        let slow = NotchMotion.spring(duration: 0.5, bounce: 0.2, speed: .turtle)
        let fast = NotchMotion.spring(duration: 0.5, bounce: 0.2, speed: .falcon)
        let human = NotchMotion.spring(duration: 0.5, bounce: 0.2, speed: .human)
        #expect(slow == .spring(duration: 0.5 / 0.7, bounce: 0.2))
        #expect(fast == .spring(duration: 0.5 / 3, bounce: 0.2))
        #expect(human == .spring(duration: 0.5, bounce: 0.2))
    }

    @Test func reduceMotionStillWinsAtEverySpeed() {
        for speed in ShellAnimationSpeed.allCases {
            UserDefaults.standard.set(speed.rawValue, forKey: AppSettings.ShellKey.speed)
            defer { UserDefaults.standard.removeObject(forKey: AppSettings.ShellKey.speed) }
            #expect(NotchMotion.expansion(true, reduceMotion: true) == .spring(response: 0.3, dampingFraction: 1))
            #expect(NotchMotion.layout(reduceMotion: true) == nil)
        }
    }
}

struct ShellSwipeTests {
    @Test func leftSwipePastThresholdStepsForward() {
        var swipe = SwipeTracker()
        _ = swipe.feed(dx: -20, dy: 1, phase: .began)
        _ = swipe.feed(dx: -40, dy: 2, phase: .changed)
        _ = swipe.feed(dx: -30, dy: 2, phase: .changed)
        let r21 = swipe.feed(dx: 0, dy: 0, phase: .ended) == .commit(delta: 1)
        #expect(r21)
    }

    @Test func rightSwipeStepsBack() {
        var swipe = SwipeTracker()
        _ = swipe.feed(dx: 90, dy: 0, phase: .began)
        let r22 = swipe.feed(dx: 0, dy: 0, phase: .ended) == .commit(delta: -1)
        #expect(r22)
    }

    @Test func shortSwipeSpringsBack() {
        var swipe = SwipeTracker()
        _ = swipe.feed(dx: -30, dy: 0, phase: .began)
        let r23 = swipe.feed(dx: 0, dy: 0, phase: .ended)
        #expect(r23 == .cancelled)
    }

    @Test func verticalScrollIsNeverTreatedAsASwipe() {
        var swipe = SwipeTracker()
        let r24 = swipe.feed(dx: 2, dy: 30, phase: .began)
        #expect(r24 == .none)
        let r25 = swipe.feed(dx: -90, dy: 30, phase: .changed)
        #expect(r25 == .none)
        let r26 = swipe.feed(dx: 0, dy: 0, phase: .ended)
        #expect(r26 == .none)
    }

    @Test func rubberBandResistsAndIsBounded() {
        let near = SwipeTracker.rubberBand(10), far = SwipeTracker.rubberBand(400)
        #expect(near > 0 && near < 10)
        #expect(far < SwipeTracker.maxStretch && far > near)
        #expect(SwipeTracker.rubberBand(-40) == -SwipeTracker.rubberBand(40))
        #expect(SwipeTracker.rubberBand(0) == 0)
    }

    @Test func flickUsesAShorterThreshold() {
        var flick = SwipeTracker(commitDistance: 30)
        _ = flick.feed(dx: 35, dy: 0, phase: .began)
        let r27 = flick.feed(dx: 0, dy: 0, phase: .ended) == .commit(delta: -1)
        #expect(r27)
    }

    @Test func pageOrderWalksHomeClipboardTrayMusicWidgets() {
        let pages = IslandPageOrder.visible(trayCount: 3, current: .home)
        #expect(IslandPageOrder.page(from: .home, delta: 1, in: pages) == .clipboard)
        #expect(IslandPageOrder.page(from: .tray, delta: 1, in: pages) == .music)
        #expect(IslandPageOrder.page(from: .music, delta: 1, in: pages) == .widgets)
        #expect(IslandPageOrder.page(from: .widgets, delta: 1, in: pages) == nil)
        #expect(IslandPageOrder.page(from: .home, delta: -1, in: pages) == nil)
        #expect(IslandPageOrder.page(from: .widgets, delta: -1, in: pages) == .music)
    }
}

struct ShellSettingsTests {
    private func settings() -> AppSettings {
        let name = "shell-settings-\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func defaultsKeepCurrentBehavior() {
        let s = settings()
        #expect(s.shellOpensOnHover && s.shellAutoCollapse && s.shellAutoExpandActivities)
        #expect(s.shellOpenDelay == 0.25 && s.shellCollapseDelay == 0.10)
        #expect(s.shellAnimationSpeed == .human)
        // Display defaults: notchless displays get the floating pill, shown when active,
        // and the island stays up in Mission Control.
        #expect(s.shellExternalVisibility == .always && s.shellExternalStyle == .island)
        #expect(!s.shellHideInMissionControl)
        #expect(!s.shellHideOnFullscreen && !s.shellHideFromCapture && s.shellHiddenApps.isEmpty)
        #expect(ShellTiming.current(s) == ShellTiming())
        #expect(ShellTuning.current(s) == ShellTuning())
    }

    @Test func slidersClampOutOfRangeValues() {
        let s = settings()
        s.shellIslandWidthOffset = 9999
        s.shellNotchHeightOffset = -9999
        s.shellCollapseDelay = 0
        #expect(s.shellIslandWidthOffset == AppSettings.ShellRange.islandWidth.upperBound)
        #expect(s.shellNotchHeightOffset == AppSettings.ShellRange.notchHeight.lowerBound)
        #expect(s.shellCollapseDelay == AppSettings.ShellRange.collapseDelay.lowerBound)
    }

    @Test func enumsRoundTripAndFallBackOnGarbage() {
        let s = settings()
        s.shellRightClickAction = .hide
        s.shellAnimationSpeed = .falcon
        #expect(s.shellRightClickAction == .hide && s.shellAnimationSpeed == .falcon)
        s.defaults.set("nonsense", forKey: AppSettings.ShellKey.speed)
        #expect(s.shellAnimationSpeed == .human)
    }
}
