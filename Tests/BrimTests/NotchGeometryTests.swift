import Foundation
import Testing
@testable import Brim

struct NotchGeometryTests {
    @Test func reduceMotionDisablesShellAndControlMovement() {
        #expect(NotchMotion.expansion(true, reduceMotion: true) == .spring(response: 0.3, dampingFraction: 1))
        #expect(NotchMotion.expansion(false, reduceMotion: true) == .spring(response: 0.3, dampingFraction: 1))
        #expect(NotchMotion.layout(reduceMotion: true) == nil)
        #expect(NotchMotion.feedback(reduceMotion: true) == nil)
        #expect(NotchMotion.expansion(true, reduceMotion: false) != nil)
    }

    @Test func hostingCanvasDoesNotResizeWhenSwitchingContent() {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -911, y: 982, width: 3440, height: 1440),
                       CGRect(x: -400, y: 0, width: 400, height: 700)] {
            let base = NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
            for music in [false, true] {
                for drawer in [false, true] {
                    var geometry = base
                    geometry.compactMusicLayout = music
                    geometry.audioDrawerExpanded = drawer
                    geometry.hasLiveActivity = true
                    #expect(geometry.hostingFrame == base.hostingFrame)
                    #expect(geometry.hostingFrame.contains(geometry.panelFrame))
                    #expect(geometry.hostingFrame.maxY == screen.maxY)
                    #expect(geometry.hostingFrame.midX == screen.midX)
                }
            }
        }
    }

    @Test func invisibleCanvasDoesNotExtendMusicHoverArea() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     notchWidth: 184, notchHeight: 32, compactMusicLayout: true)
        let outsideMusic = CGPoint(x: geometry.hostingFrame.minX + 10, y: geometry.hostingFrame.minY + 10)
        #expect(geometry.hostingFrame.contains(outsideMusic))
        #expect(!geometry.containsPointer(outsideMusic, expanded: true))
    }

    @Test func hoverIncludesTopEdgeOnVerticallyStackedExternalDisplay() {
        let external = NotchGeometry(screenFrame: CGRect(x: -911, y: 982, width: 3440, height: 1440),
                                     notchWidth: 0, notchHeight: 0, hasLiveActivity: true, compactMusicLayout: true)
        #expect(external.containsPointer(CGPoint(x: 809, y: 2422), expanded: false))
        #expect(external.containsPointer(CGPoint(x: 809, y: 2422), expanded: true))
        #expect(!external.containsPointer(CGPoint(x: 809, y: 2423), expanded: false))
        #expect(!external.containsPointer(CGPoint(x: 809, y: 980), expanded: false))
        #expect(!external.containsPointer(CGPoint(x: 500, y: 2422), expanded: false))
    }

    @Test func hoverIncludesTopEdgeOnLeftAndMainDisplays() {
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: -100)] {
            let geometry = NotchGeometry(screenFrame: CGRect(origin: origin, size: CGSize(width: 1512, height: 982)),
                                         notchWidth: 184, notchHeight: 32)
            #expect(geometry.containsPointer(CGPoint(x: geometry.screenFrame.midX, y: geometry.screenFrame.maxY), expanded: false))
        }
    }

    @Test func anchorsToOffsetDisplayAndKeepsContentBelowNotch() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: -1512, y: 200, width: 1512, height: 982), notchWidth: 184, notchHeight: 32)
        #expect(geometry.panelFrame.midX == -756)
        #expect(geometry.panelFrame.maxY == 1182)
        #expect(geometry.triggerFrame.minY == 1150)
        #expect(geometry.collapsedSize.width == 184)
        #expect(geometry.collapsedSize.height == 32)
        #expect(geometry.expandedSize.width == 600)
        #expect(geometry.expandedSize.height > geometry.collapsedSize.height)
    }

    @Test func audioDrawerGrowsDownwardWithoutMovingTheTrigger() {
        let closed = NotchGeometry(screenFrame: CGRect(x: 1512, y: -100, width: 2560, height: 1440), notchWidth: 0, notchHeight: 0, topInset: 30, compactMusicLayout: true)
        var opened = closed
        opened.audioDrawerExpanded = true
        #expect(opened.panelFrame.maxY == closed.panelFrame.maxY)
        #expect(opened.panelFrame.height == closed.panelFrame.height + 133)
        #expect(opened.triggerFrame == closed.triggerFrame)
    }

    @Test func musicLayoutUsesCompactHeightAndDrawerKeepsTopAnchor() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 184, notchHeight: 32, compactMusicLayout: true)
        #expect(geometry.expandedSize.height == 216.8)
        var drawer = geometry
        drawer.audioDrawerExpanded = true
        #expect(drawer.expandedSize.height == 349.8)
        #expect(drawer.panelFrame.maxY == geometry.panelFrame.maxY)
    }

    @Test func narrowMusicSurfaceScalesDrawerAndPlayerTogether() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 504, height: 900), notchWidth: 0, notchHeight: 0, audioDrawerExpanded: true, compactMusicLayout: true)
        #expect(geometry.expandedSize == CGSize(width: 420, height: 317.8))
        #expect(geometry.panelFrame.maxY == 900)
    }

    @Test func fallbackFitsSmallDisplay() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 400, height: 700), notchWidth: 0, notchHeight: 0)
        #expect(geometry.expandedSize.width == 376)
        #expect(geometry.collapsedSize.height == 37)
        #expect(geometry.triggerFrame.height == 37)
        #expect(geometry.panelFrame.minX >= 0)
    }

    @Test func externalIslandIsVisibleAndFollowsItsOwnDisplayCoordinates() {
        let external = NotchGeometry(screenFrame: CGRect(x: 1512, y: -100, width: 2560, height: 1440),
                                     notchWidth: 0, notchHeight: 0, topInset: 30, hasLiveActivity: true)
        #expect(external.isFloating)
        #expect(external.collapsedSize == CGSize(width: 230, height: 37))
        #expect(external.panelFrame.midX == 2792)
        #expect(external.panelFrame.maxY == 1310)
        #expect(external.triggerFrame.contains(CGPoint(x: 2792, y: 1290)))
        #expect(!external.triggerFrame.contains(CGPoint(x: 756, y: 970)))
    }

    @Test func secondaryDisplayUsesAttachedNotchFallback() {
        let external = NotchGeometry.simulatedExternal(
            screenFrame: CGRect(x: 1512, y: -100, width: 2560, height: 1440)
        )
        #expect(!external.isFloating)
        #expect(external.isSimulatedNotch)
        #expect(external.collapsedSize == CGSize(width: 184, height: 32))
        #expect(external.triggerFrame.maxY == external.screenFrame.maxY)
        #expect(external.panelFrame.maxY == external.screenFrame.maxY)
    }

    @Test func liveActivityFitsBesidePhysicalNotchAndUsesSameHoverFootprint() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     notchWidth: 184, notchHeight: 32, hasLiveActivity: true)
        // Each wing: the shape's 8pt shoulder + 14pt inset + 25pt glyph + 8pt gap to the housing.
        #expect(geometry.collapsedSize == CGSize(width: 184 + 2 * (8 + 14 + 25 + 8), height: 32))
        #expect(geometry.triggerFrame.width == geometry.collapsedSize.width)
        #expect(!geometry.triggerFrame.contains(CGPoint(x: 756, y: 949)))
    }

    /// The camera housing hides whatever sits under it, so each wing must hold the glyph with room to spare.
    @Test func compactGlyphNeverSlidesUnderThePhysicalNotch() {
        for activity in [IslandActivity.music, .recording, .agent, .devices] {
            for secondary in [false, true] {
                let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                             notchWidth: 185, notchHeight: 32, hasLiveActivity: true,
                                             hasSecondaryActivity: secondary, compactActivity: activity)
                let wing = (geometry.collapsedSize.width - geometry.notchWidth) / 2
                #expect(wing >= NotchGeometry.compactWingMinimum,
                        "\(activity) secondary=\(secondary): wing \(wing) < \(NotchGeometry.compactWingMinimum)")
            }
        }
        #expect(NotchGeometry.compactWingMinimum >= 14 + 25 + 4)
    }

    /// The right wing's value ("43.7k", "80%") must start clear of the housing, not under it.
    @Test func compactTrailingValueFitsBesideThePhysicalNotch() {
        for activity in [IslandActivity.agent, .devices, .system, .music, .call, .focus] {
            let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                         notchWidth: 185, notchHeight: 32, hasLiveActivity: true,
                                         compactActivity: activity)
            let wing = (geometry.collapsedSize.width - geometry.notchWidth) / 2
            let needed = NotchGeometry.compactPadding + NotchGeometry.compactTrailingWidth(for: activity)
                + NotchGeometry.hardwareClearance
            #expect(wing >= needed, "\(activity): wing \(wing) < \(needed)")
        }
        #expect(NotchGeometry.compactTrailingWidth(for: .agent) >= 40)
    }

    @Test func hoverRequiresDwellAndAllowsGracePeriod() {
        var hover = ShelfHoverState()
        for (inside, time, expected) in [(true, 0.0, false), (true, 0.26, true), (false, 1.0, true), (false, 1.05, true), (false, 1.11, false)] {
            let expanded = hover.update(isInside: inside, isDragging: false, now: time)
            #expect(expanded == expected)
        }
    }

    @Test func draggingAndReentryKeepShelfOpen() {
        var hover = ShelfHoverState()
        _ = hover.update(isInside: true, isDragging: false, now: 0)
        _ = hover.update(isInside: true, isDragging: false, now: 0.3)
        for (inside, dragging, time) in [(false, true, 10.0), (true, false, 11.0), (false, false, 12.0), (true, false, 12.4)] {
            let expanded = hover.update(isInside: inside, isDragging: dragging, now: time)
            #expect(expanded)
        }
        hover.reset()
        #expect(!hover.isExpanded)
    }

    @Test func activityOutsideNotchNeverOpensShelf() {
        var hover = ShelfHoverState()
        for time in [0.0, 1, 10, 100] {
            let idleExpanded = hover.update(isInside: false, isDragging: false, now: time)
            let draggingExpanded = hover.update(isInside: false, isDragging: true, now: time)
            #expect(!idleExpanded)
            #expect(!draggingExpanded)
        }
    }

    @Test func briefPassAcrossNotchDoesNotOpenShelf() {
        var hover = ShelfHoverState()
        for (inside, time, expected) in [(true, 0.0, false), (false, 0.08, false), (true, 1.0, false),
                                         (true, 1.2, false), (true, 1.3, true)] {
            let expanded = hover.update(isInside: inside, isDragging: false, now: time)
            #expect(expanded == expected)
        }
    }

    @Test func areaBelowHardwareNotchCannotTriggerExpansion() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 184, notchHeight: 32)
        #expect(geometry.triggerFrame.contains(CGPoint(x: 756, y: 960)))
        #expect(!geometry.triggerFrame.contains(CGPoint(x: 756, y: 949)))
        #expect(!geometry.triggerFrame.contains(CGPoint(x: 650, y: 960)))
    }
}

struct IslandBubbleCanvasTests {
    @Test(arguments: [400.0, 800.0, 1512.0, 1920.0], [1.0, 1.18])
    func expandedBubblesStayInsideNativeWindow(width: Double, scale: Double) {
        for floating in [false, true] {
            let screen = CGRect(x: -600, y: 200, width: width, height: 982)
            var geometry = floating ? NotchGeometry.dynamicIsland(screenFrame: screen)
                : NotchGeometry(screenFrame: screen, notchWidth: 185, notchHeight: 32)
            geometry.tuning.openScale = scale
            geometry.utilityContentHeight = 200
            geometry.preferredWidth = 740
            let stableCanvas = geometry.hostingFrame
            geometry.hasLeadingBubble = true
            geometry.hasSecondaryActivity = true
            #expect(geometry.hostingFrame == stableCanvas)
            for expanded in [false, true] {
                for side in IslandBubbleSide.allCases {
                    let bubble = geometry.bubbleFrame(side, expanded: expanded)
                    #expect(geometry.hostingFrame.insetBy(dx: -0.01, dy: -0.01).contains(bubble),
                            "Native window clips \(side) bubble, width=\(width), scale=\(scale), expanded=\(expanded)")
                    #expect(screen.insetBy(dx: -0.01, dy: -0.01).contains(bubble))
                }
            }
        }
    }
}
