import AppKit
import Foundation
import Testing

@testable import Brim

/// Ranking and placement of the two detached bubbles (iPhone's split Dynamic Island).
struct IslandBubbleRankingTests {
  @Test func musicKeepsTheIslandTimerAndAgentTakeTheBubbles() {
    let state = IslandActivities(recording: false, call: false, music: true, timer: true, additional: [.agent])
    #expect(state.primary == .music)
    #expect(state.secondary == .timer)
    #expect(state.tertiary == .agent)
    let pair = state.bubbles(beside: state.primary)
    #expect(pair == IslandBubblePair(leading: .agent, trailing: .timer))
  }

  @Test func atMostTwoBubblesBestRankedFirst() {
    let state = IslandActivities(recording: true, call: false, music: true, timer: true,
                                 additional: [.agent, .download, .build])
    #expect(state.primary == .recording)
    // A playing song always rides in a bubble; then the next ranked live activity.
    #expect(state.companions(to: state.primary) == [.music, .timer])
    #expect(state.bubbles(beside: state.primary).count == 2)
  }

  @Test func ambientSkinsNeverTakeABubble() {
    let state = IslandActivities(recording: false, call: false, music: true, additional: [.browser, .workspace, .agent])
    #expect(state.companions(to: .music) == [.agent])
    #expect(state.tertiary == nil)
    let browserOnly = IslandActivities(recording: false, call: false, music: true, additional: [.browser])
    #expect(browserOnly.secondary == nil)
    #expect(browserOnly.bubbles(beside: .music).isEmpty)
  }

  /// Like iPhone: a lone bubble always hangs on the right, whatever it is.
  @Test func aSingleBubbleIsAlwaysOnTheRight() {
    let timer = IslandActivities(recording: false, call: false, music: true, timer: true)
    #expect(timer.bubbles(beside: .music) == IslandBubblePair(trailing: .timer))
    let agent = IslandActivities(recording: false, call: false, music: true, additional: [.agent])
    #expect(agent.bubbles(beside: .music) == IslandBubblePair(trailing: .agent))
    let download = IslandActivities(recording: false, call: false, music: true, additional: [.download])
    #expect(download.bubbles(beside: .music) == IslandBubblePair(trailing: .download))
    let call = IslandActivities(recording: false, call: true, music: true)
    #expect(call.bubbles(beside: .call) == IslandBubblePair(trailing: .music))
  }

  /// Two bubbles: the second-ranked activity on the right, the third on the left.
  @Test func secondRightThirdLeft() {
    #expect(IslandBubblePair.placing([.timer, .agent]) == IslandBubblePair(leading: .agent, trailing: .timer))
    #expect(IslandBubblePair.placing([.music, .timer]) == IslandBubblePair(leading: .timer, trailing: .music))
    #expect(IslandBubblePair.placing([]) == .none)
  }

  /// A bubble already on the right stays there when another arrives, even one that outranks it:
  /// the newcomer takes the left. And a left bubble stays left while the right one changes.
  @Test func sidesStayPutWhenTheRankingShifts() {
    let agentAlone = IslandBubblePair.placing([.agent])
    #expect(agentAlone == IslandBubblePair(trailing: .agent))
    // The timer outranks the agent, but the agent keeps the right.
    let withTimer = IslandBubblePair.placing([.timer, .agent], after: agentAlone)
    #expect(withTimer == IslandBubblePair(leading: .timer, trailing: .agent))
    // Re-ranking (an agent asking for input) never swaps a pair that is already showing.
    #expect(IslandBubblePair.placing([.agent, .timer], after: withTimer) == withTimer)
    // The right one ends and a new one arrives: the left one stays left.
    #expect(IslandBubblePair.placing([.download, .timer], after: withTimer)
            == IslandBubblePair(leading: .timer, trailing: .download))
    // Back to one: it moves to the right.
    #expect(IslandBubblePair.placing([.timer], after: withTimer) == IslandBubblePair(trailing: .timer))
  }
}

@MainActor
struct IslandBubblePresentationTests {
  @Test func presentationLaysOutBothSidesAndHidesThemForHUDs() {
    let presentation = NotchPresentation()
    presentation.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          notchWidth: 185, notchHeight: 32)
    let state = IslandActivities(recording: false, call: false, music: true, timer: true, additional: [.agent])
    presentation.updateActivities(state, route: .activity(.music))
    #expect(presentation.geometry.hasLeadingBubble)
    #expect(presentation.geometry.hasSecondaryActivity)
    #expect(presentation.bubbleActivity(.leading) == .agent)
    #expect(presentation.bubbleActivity(.trailing) == .timer)
    // Polling again with the same activities keeps both where they are.
    presentation.updateActivities(IslandActivities(recording: false, call: false, music: true, timer: true,
                                                   additional: [.agent, .browser]), route: .activity(.music))
    #expect(presentation.bubbles == IslandBubblePair(leading: .agent, trailing: .timer))
    let flash = IslandFlash(title: "Volume", symbol: "speaker.fill", tint: .green, value: 0.4, until: .distantFuture)
    presentation.updateActivities(state, route: .hud(flash))
    #expect(!presentation.geometry.hasBubble)
    presentation.updateActivities(state, route: .notification)
    #expect(!presentation.geometry.hasBubble)
  }

  @Test func showingABubbleOpensItsActivity() {
    let presentation = NotchPresentation()
    presentation.showBubble(.agent)
    #expect(presentation.selectedActivity == .agent)
  }
}

/// Where the bubbles sit and what answers the pointer, on the notch and on the floating pill.
struct IslandBubbleGeometryTests {
  static let notch = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   notchWidth: 185, notchHeight: 32, hasLiveActivity: true, compactActivity: .music)
  static var pill: NotchGeometry {
    var geometry = NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
    geometry.hasLiveActivity = true
    geometry.compactActivity = .music
    return geometry
  }

  private func both(_ base: NotchGeometry) -> NotchGeometry {
    var geometry = base
    geometry.hasSecondaryActivity = true
    geometry.hasLeadingBubble = true
    return geometry
  }

  @Test(arguments: [false, true]) func bubblesMirrorAboutTheIsland(floating: Bool) {
    let geometry = both(floating ? Self.pill : Self.notch)
    for expanded in [false, true] {
      let main = expanded ? geometry.panelFrame : geometry.triggerFrame
      let left = geometry.bubbleFrame(.leading, expanded: expanded)
      let right = geometry.bubbleFrame(.trailing, expanded: expanded)
      #expect(right == geometry.secondaryFrame(expanded: expanded))
      #expect(abs((main.minX - left.maxX) - (right.minX - main.maxX)) < 0.01)
      #expect(abs(main.minX - left.maxX - NotchGeometry.bubbleGap) < 0.01)
      #expect(left.size == right.size && left.minY == right.minY)
      #expect(left.width == left.height, "a bubble is a circle")
      #expect(geometry.hostingFrame.contains(left) && geometry.hostingFrame.contains(right),
              "both bubbles inside the window (expanded \(expanded))")
    }
    // Two bubbles: the pill stays centred; the notch never moves off the camera.
    #expect(geometry.collapsedMainOffset == 0)
    #expect(geometry.triggerFrame.midX == geometry.screenFrame.midX)
  }

  @Test func bubbleDiameterIsTheIslandHeight() {
    #expect(Self.notch.secondarySize == CGSize(width: 32, height: 32))
    #expect(Self.pill.secondarySize.height == Self.pill.collapsedSize.height)
  }

  @Test func oneBubbleOnThePillCentresTheGroup() {
    var left = Self.pill
    left.hasLeadingBubble = true
    var right = Self.pill
    right.hasSecondaryActivity = true
    let room = left.secondarySize.width + NotchGeometry.bubbleGap
    #expect(left.collapsedMainOffset == room / 2)
    #expect(right.collapsedMainOffset == -room / 2)
    // The group (bubble + gap + pill) is centred on the display.
    let group = left.bubbleFrame(.leading, expanded: false).union(left.triggerFrame)
    #expect(abs(group.midX - left.screenFrame.midX) < 0.01)
  }

  @Test func bubblesNeverCoverTheCameraHousing() {
    let geometry = both(Self.notch)
    let housing = CGRect(x: geometry.screenFrame.midX - geometry.notchWidth / 2, y: geometry.screenFrame.maxY - 32,
                         width: geometry.notchWidth, height: 32)
    for side in IslandBubbleSide.allCases {
      #expect(!geometry.bubbleFrame(side, expanded: false).intersects(housing), "\(side)")
    }
    // Wings beside the camera are unchanged by bubbles: they hang outside the island.
    #expect(geometry.collapsedSize == Self.notch.collapsedSize)
  }

  @Test(arguments: [false, true]) func pointerFindsEachBubble(floating: Bool) {
    let geometry = both(floating ? Self.pill : Self.notch)
    for expanded in [false, true] {
      for side in IslandBubbleSide.allCases {
        let frame = geometry.bubbleFrame(side, expanded: expanded)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        #expect(geometry.bubble(at: center, expanded: expanded) == side)
        #expect(geometry.containsPointer(center, expanded: expanded))
        // The gap between bubble and island keeps hover, without counting as the bubble.
        let gap = CGPoint(x: side == .leading ? frame.maxX + 3 : frame.minX - 3, y: frame.midY)
        #expect(geometry.containsPointer(gap, expanded: expanded))
        #expect(geometry.bubble(at: gap, expanded: expanded) == nil)
        // Beyond the bubble and beneath it: nothing.
        let outside = CGPoint(x: side == .leading ? frame.minX - 3 : frame.maxX + 3, y: frame.midY)
        #expect(!geometry.containsPointer(outside, expanded: expanded))
        #expect(geometry.bubble(at: CGPoint(x: frame.midX, y: frame.minY - 20), expanded: expanded) == nil)
      }
    }
    var trailingOnly = geometry
    trailingOnly.hasLeadingBubble = false
    let left = trailingOnly.bubbleFrame(.leading, expanded: false)
    #expect(trailingOnly.bubble(at: CGPoint(x: left.midX, y: left.midY), expanded: false) == nil)
    #expect(!trailingOnly.containsPointer(CGPoint(x: left.midX, y: left.midY), expanded: false))
  }

  /// The open island leaves room for a bubble on each side on a narrow display.
  @Test func openWidthClampLeavesRoomForBothBubbles() {
    var geometry = both(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 640, height: 480),
                                      notchWidth: 185, notchHeight: 32, hasLiveActivity: true))
    geometry.hasLeadingBubble = true
    let left = geometry.bubbleFrame(.leading, expanded: true)
    let right = geometry.bubbleFrame(.trailing, expanded: true)
    #expect(left.minX >= geometry.screenFrame.minX + 12 - 0.01)
    #expect(right.maxX <= geometry.screenFrame.maxX - 12 + 0.01)
    var leftOnly = geometry
    leftOnly.hasSecondaryActivity = false
    #expect(leftOnly.expandedSize.width == geometry.expandedSize.width, "the open island stays centred")
  }
}

struct TimerBubbleReadoutTests {
  @Test func readoutFitsInsideTheRing() {
    #expect(TimerBubble.text(2 * 3600 + 5) == "2h")
    #expect(TimerBubble.text(3599) == "1h")
    #expect(TimerBubble.text(24 * 60 + 59) == "25m")
    #expect(TimerBubble.text(24 * 60) == "24m")
    #expect(TimerBubble.text(61) == "2m")
    #expect(TimerBubble.text(60) == "1m")
    #expect(TimerBubble.text(41.2) == "42s")
    #expect(TimerBubble.text(.nan) == "0s")
    // Never more than three characters plus the unit: nothing to clip at 12pt in a 24pt disc.
    for seconds in stride(from: 0.0, through: 99 * 3600, by: 37) {
      #expect(TimerBubble.readout(seconds).value.count <= 2, "\(seconds)")
    }
  }

  /// The widest readout ("88m") measured in SF Rounded fits the ring's clear disc, at the height of
  /// its digits, with a point to spare each side: nothing is clipped or touches the ring.
  @Test(arguments: [CGFloat(32), 37]) func widestReadoutClearsTheRing(diameter: CGFloat) {
    func rounded(_ size: CGFloat) -> NSFont {
      let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
      return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    let value = rounded(IslandBubbleMetrics.valueSize(diameter))
    let unit = rounded(IslandBubbleMetrics.unitSize(diameter))
    let width = ("88" as NSString).size(withAttributes: [.font: value, .kern: IslandBubbleMetrics.valueTracking]).width
      + ("m" as NSString).size(withAttributes: [.font: unit]).width
    let radius = IslandBubbleMetrics.innerDiameter(diameter) / 2
    let halfHeight = value.capHeight / 2
    let chord = 2 * (radius * radius - halfHeight * halfHeight).squareRoot()
    #expect(width + 2 <= chord, "readout \(width)pt in a \(chord)pt chord at \(diameter)pt")
  }

  @Test func statesFollowTheClock() {
    #expect(TimerBubble.state(remaining: 600, paused: false, done: false) == .running)
    #expect(TimerBubble.state(remaining: 59, paused: false, done: false) == .nearEnd)
    #expect(TimerBubble.state(remaining: 59, paused: true, done: false) == .paused)
    #expect(TimerBubble.state(remaining: 0, paused: false, done: true) == .done)
  }
}

/// The island and its bubbles never show the same activity: the Music page owns the song even
/// when another card (an agent asking, a recording, a clicked timer) was selected before.
struct IslandOwnerTests {
  @Test func musicPageTakesTheSongOutOfTheBubbles() {
    let asking = IslandActivities(recording: false, call: false, music: true, agentNeedsInput: true, additional: [.agent])
    #expect(asking.primary == .agent)
    let owner = asking.islandOwner(expanded: true, selected: .agent, showingMusic: true)
    #expect(owner == .music)
    #expect(!asking.companions(to: owner).contains(.music))
    #expect(asking.companions(to: owner).contains(.agent))
  }

  @Test func selectedCardOwnsTheIslandAwayFromMusic() {
    let state = IslandActivities(recording: true, call: false, music: true)
    let owner = state.islandOwner(expanded: true, selected: .recording, showingMusic: false)
    #expect(owner == .recording)
    #expect(state.companions(to: owner) == [.music])
  }

  @Test func closedIslandFollowsTheLeader() {
    let state = IslandActivities(recording: false, call: false, music: true, timer: true)
    #expect(state.islandOwner(expanded: false, selected: .timer, showingMusic: true) == state.primary)
  }

  /// The user's case: switching back and forth between the agent bubble and the Music page.
  @Test func switchingBackAndForthNeverDuplicatesTheSong() {
    let state = IslandActivities(recording: false, call: false, music: true, agentNeedsInput: true, additional: [.agent])
    for (selected, music) in [(IslandActivity.agent, false), (.agent, true), (nil, true), (.agent, false), (.agent, true)] {
      let owner = state.islandOwner(expanded: true, selected: selected, showingMusic: music)
      #expect(!state.companions(to: owner).contains(owner ?? .system))
    }
  }
}
