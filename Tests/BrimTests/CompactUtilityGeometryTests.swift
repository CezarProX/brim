import Foundation
import Testing
@testable import Brim

struct CompactUtilityGeometryTests {
    @Test func utilityCardAndHoverUseTheSameCompactFrame() {
        var geometry = NotchGeometry.simulatedExternal(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        geometry.utilityContentHeight = 238
        #expect(geometry.expandedSize == CGSize(width: 480, height: 270))
        #expect(!geometry.isFloating)
        #expect(geometry.containsPointer(CGPoint(x: geometry.panelFrame.midX, y: 1080), expanded: true))
        // The gap between the shell and the navigation capsule counts as the island across the shell's
        // whole width, so a diagonal move from a corner to a tab never closes it.
        #expect(geometry.containsPointer(CGPoint(x: geometry.panelFrame.midX, y: geometry.panelFrame.minY - 1), expanded: true))
        #expect(geometry.containsPointer(CGPoint(x: geometry.panelFrame.minX + 10, y: geometry.panelFrame.minY - 1), expanded: true))
        // Beside the capsule (not above it) and under it is outside.
        #expect(!geometry.containsPointer(CGPoint(x: geometry.panelFrame.minX + 10, y: geometry.navigationFrame.midY), expanded: true))
        #expect(!geometry.containsPointer(CGPoint(x: geometry.panelFrame.midX,
                                                  y: geometry.navigationFrame.minY - NotchGeometry.capsuleSlack - 1), expanded: true))
        geometry.utilityContentHeight = 300
        #expect(geometry.expandedSize.height == 332)
        #expect(geometry.hostingFrame.contains(geometry.panelFrame))
    }

    @Test func openIslandForgivesDriftingJustPastTheTabs() {
        let geometry = NotchGeometry.simulatedExternal(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let tabs = geometry.navigationFrame
        let underTabs = CGPoint(x: tabs.midX, y: tabs.minY - NotchGeometry.capsuleSlack - 10)
        // Not part of the island for clicks, but not a leave either.
        #expect(!geometry.containsPointer(underTabs, expanded: true))
        #expect(geometry.keepsOpen(underTabs))
        #expect(geometry.keepsOpen(CGPoint(x: tabs.minX - 10, y: tabs.midY)))
        #expect(geometry.keepsOpen(CGPoint(x: geometry.panelFrame.maxX + 10, y: geometry.panelFrame.midY)))
        // Past the margin it closes.
        #expect(!geometry.keepsOpen(CGPoint(x: tabs.midX, y: tabs.minY - NotchGeometry.exitMargin - 1)))
        #expect(!geometry.keepsOpen(CGPoint(x: geometry.panelFrame.maxX + NotchGeometry.exitMargin + 1,
                                            y: geometry.panelFrame.midY)))
    }

    @Test func musicSummaryDoesNotMoveOrResizeCompactPlayback() {
        var geometry = NotchGeometry.simulatedExternal(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        geometry.compactMusicLayout = true
        let compact = geometry.collapsedSize
        let height = geometry.expandedSize.height
        geometry.musicSummaryHeight = 48
        #expect(geometry.expandedSize.height == height + 48)
        #expect(geometry.collapsedSize == compact)
        geometry.audioDrawerExpanded = true
        #expect(geometry.hostingFrame.height >= geometry.expandedSize.height)
    }
}
