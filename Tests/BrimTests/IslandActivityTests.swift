import Foundation
import Testing
@testable import Brim

struct IslandActivityTests {
    @Test func recordingTakesPriorityAndMusicRemainsSecondary() {
        let state = IslandActivities(recording: true, call: false, music: true)
        #expect(state.primary == .recording)
        #expect(state.secondary == .music)
        #expect(state.selected(.music) == .music)
    }

    @Test func endingRecordingRestoresMusicAndClearsStaleSelection() {
        let state = IslandActivities(recording: false, call: false, music: true)
        #expect(state.primary == .music)
        #expect(state.secondary == nil)
        #expect(state.selected(.recording) == .music)
    }

    @Test func callAndMusicUseTwoActivities() {
        let state = IslandActivities(recording: false, call: true, music: true)
        #expect(state.primary == .call)
        #expect(state.secondary == .music)
    }

    @Test func threeActivitiesKeepMusicInBubbleAndCallAccessible() {
        let state = IslandActivities(recording: true, call: true, music: true)
        #expect(state.primary == .recording)
        #expect(state.secondary == .music)
        #expect(state.selected(.call) == .call)
        #expect(state.companion(to: .music) == .recording)
    }

    @Test func idleHasNoActivities() {
        let state = IslandActivities(recording: false, call: false, music: false)
        #expect(state.primary == nil)
        #expect(state.secondary == nil)
    }
}

struct IslandSecondaryGeometryTests {
    @Test("Secondary activity and the gap remain hoverable on both display types", arguments: [true, false])
    func secondaryHover(floating: Bool) {
        var geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     notchWidth: floating ? 0 : 184, notchHeight: floating ? 0 : 32)
        geometry.hasLiveActivity = true
        geometry.hasSecondaryActivity = true
        for expanded in [true, false] {
            let bubble = geometry.secondaryFrame(expanded: expanded)
            #expect(geometry.containsPointer(CGPoint(x: bubble.midX, y: bubble.midY), expanded: expanded))
            #expect(geometry.containsPointer(CGPoint(x: bubble.minX - 4, y: bubble.midY), expanded: expanded))
            #expect(geometry.hostingFrame.contains(bubble))
            if expanded {
                #expect(!geometry.containsPointer(CGPoint(x: bubble.midX, y: bubble.minY - 40), expanded: true),
                        "Invisible canvas beneath the bubble must not steal pointer input")
            }
            geometry.hasSecondaryActivity = false
            if expanded {
                #expect(!geometry.containsPointer(CGPoint(x: bubble.midX, y: bubble.midY), expanded: expanded))
            }
            geometry.hasSecondaryActivity = true
        }
    }
}

@MainActor
struct IslandPresentationTests {
    @Test func unrelatedActivityEndingPreservesSelectedCompanionGeometry() {
        let presentation = NotchPresentation()
        presentation.isExpanded = true
        presentation.updateActivities(IslandActivities(recording: true, call: true, music: false, timer: true))
        presentation.selectedActivity = .timer
        presentation.updateActivities(IslandActivities(recording: true, call: false, music: false, timer: true))
        #expect(presentation.selectedActivity == .timer)
        #expect(presentation.geometry.secondaryActivity == .recording)
    }

    @Test func recordingInterruptsMusicAndRestoresItAfterStopping() {
        let presentation = NotchPresentation()
        presentation.updateActivities(IslandActivities(recording: false, call: false, music: true))
        presentation.selectedActivity = .music
        presentation.isPresentingAudioOutputs = true
        presentation.updateActivities(IslandActivities(recording: true, call: false, music: true))
        #expect(presentation.selectedActivity == nil)
        #expect(!presentation.isPresentingAudioOutputs)
        #expect(presentation.geometry.hasLiveActivity)
        // A single bubble always hangs on the right, like iPhone's.
        #expect(presentation.geometry.hasSecondaryActivity)
        #expect(!presentation.geometry.hasLeadingBubble)
        #expect(presentation.activities.selected(presentation.selectedActivity) == .recording)
        presentation.selectedActivity = .music
        presentation.updateActivities(IslandActivities(recording: true, call: false, music: true))
        #expect(presentation.selectedActivity == .music, "Unchanged polling must preserve user selection")
        presentation.updateActivities(IslandActivities(recording: false, call: false, music: true))
        #expect(presentation.activities.selected(presentation.selectedActivity) == .music)
        #expect(!presentation.geometry.hasBubble)
        presentation.updateActivities(IslandActivities(recording: false, call: false, music: false))
        #expect(!presentation.geometry.hasLiveActivity)
    }
}

struct CompactTimerReadoutTests {
    @Test func timeReadoutDoesNotLoseLastFractionOfSecond() {
        #expect(CompactTimerReadout.format(59.2) == "1:00")
        #expect(CompactTimerReadout.format(0) == "0:00")
        #expect(CompactTimerReadout.format(-4) == "0:00")
        #expect(CompactTimerReadout.format(3601) == "1:00:01")
        #expect(CompactTimerReadout.format(.infinity) == "0:00")
        #expect(CompactTimerReadout.format(36_001, minimal: true) == "10h00")
    }
}

struct IslandAnnouncementTests {
    @Test func newActivityPeeksOnceAndRetracts() {
        var state = IslandAnnouncement()
        for (primary, time, expected) in [(IslandActivity.music, 0.0, false), (.recording, 1, true),
                                          (.recording, 2, true), (.recording, 4, false), (.music, 5, false), (.timer, 6, true)] {
            let actual = state.update(primary: primary, now: time)
            #expect(actual == expected)
        }
        state.dismiss()
        let afterDismiss = state.update(primary: .timer, now: 6.5)
        #expect(!afterDismiss)
    }

    @Test func playingMusicKeepsTheIslandAndTheTimerTakesTheBubble() {
        let state = IslandActivities(recording: false, call: false, music: true, timer: true)
        #expect(state.primary == .music)
        #expect(state.secondary == .timer)
        #expect(state.companion(to: .timer) == .music)
        #expect(state.selected(.recording) == .music)
        let focus = IslandActivities(recording: false, call: false, music: true, additional: [.focus])
        #expect(focus.primary == .music)
        #expect(focus.secondary == .focus)
    }

    /// The bubble's readout is never wider than two digits and a unit (see TimerBubbleReadoutTests).
    @Test func timerBubblePrintsWhatFitsInACircle() {
        #expect(TimerBubble.text(2 * 3600 + 5) == "2h")
        #expect(TimerBubble.text(24 * 60 + 59) == "25m")
        #expect(TimerBubble.text(600) == "10m")
        #expect(TimerBubble.text(599) == "10m")
        #expect(TimerBubble.text(60) == "1m")
        #expect(TimerBubble.text(41.2) == "42s")
        #expect(TimerBubble.text(.nan) == "0s")
    }
}

struct MusicPriorityTests {
  @Test func playingMusicLeadsOverCodingAgentsAndKeepAwake() {
    let state = IslandActivities(recording: false, call: false, music: true, additional: [.agent, .keepAwake, .browser])
    #expect(state.primary == .music)
  }
}
