import Testing
@testable import Brim

struct CallActivityTests {
    @Test func runningAppAndIncomingCallAreNotActiveEvidence() {
        #expect(CallEvidence.detect(app: .faceTime, buttons: []) == nil)
        #expect(CallEvidence.detect(app: .faceTime, buttons: ["Accept", "Decline", "Mute"]) == nil)
        #expect(CallEvidence.detect(app: .zoom, buttons: ["Join", "Mute"]) == nil)
    }

    @Test func exactControlsDetectCallAndState() {
        let call = CallEvidence.detect(app: .zoom, buttons: ["Leave", "Unmute", "Start Video"])
        #expect(call?.isMuted == true)
        #expect(call?.isCameraOn == false)
        #expect(call?.endLabel == "leave")
        #expect(CallEvidence.detect(app: .whatsApp, buttons: ["End call", "Mute"])?.isMuted == false)
        #expect(CallEvidence.detect(app: .faceTime, buttons: ["End Call", "Unmute"])?.isMuted == true)
        #expect(CallEvidence.detect(app: .discord, buttons: ["Disconnect", "Mute"]) != nil)
        #expect(CallEvidence.detect(app: .teams, buttons: ["Leave", "Unmute"]) != nil)
        #expect(CallEvidence.detect(app: .phone, buttons: ["End", "Mute"]) != nil)
    }

    @Test func ambiguousOrUnrelatedLabelsDoNotBecomeActions() {
        #expect(CallEvidence.detect(app: .zoom, buttons: ["Leave a review", "Mute notifications"]) == nil)
        #expect(CallEvidence.detect(app: .zoom, buttons: ["Leave", "Mute", "Unmute"]) == nil)
        #expect(CallEvidence.detect(app: .zoom, buttons: ["Leave", "Mute", "Mute"]) == nil)
        #expect(CallEvidence.detect(app: .zoom, buttons: ["Leave"]) == nil)
        #expect(CallEvidence.detect(app: .faceTime, buttons: ["End call", "Mute", "Start Video", "Stop Video"])?.cameraLabel == nil)
    }

    @Test func exactScreenShareControlsExposeState() {
        let zoomIdle = CallEvidence.detect(app: .zoom, buttons: ["Leave", "Mute", "Share Screen"])
        #expect(zoomIdle?.screenShareLabel == "share screen")
        #expect(zoomIdle?.isScreenSharing == false)

        let zoomSharing = CallEvidence.detect(app: .zoom, buttons: ["Leave", "Mute", "Stop Share"])
        #expect(zoomSharing?.screenShareLabel == "stop share")
        #expect(zoomSharing?.isScreenSharing == true)

        let meetSharing = CallEvidence.detect(
            app: .googleMeet,
            buttons: ["Leave call", "Turn off microphone (⌘ + d)", "Stop presenting"]
        )
        #expect(meetSharing?.screenShareLabel == "stop presenting")
        #expect(meetSharing?.isScreenSharing == true)
    }

    @Test func ambiguousOrUnrecognizedScreenShareControlsAreUnavailable() {
        let ambiguous = CallEvidence.detect(
            app: .zoom,
            buttons: ["Leave", "Mute", "Share Screen", "Stop Share"]
        )
        #expect(ambiguous?.screenShareLabel == nil)
        #expect(ambiguous?.isScreenSharing == nil)

        let unrelated = CallEvidence.detect(
            app: .teams,
            buttons: ["Leave", "Mute", "Share a file"]
        )
        #expect(unrelated?.screenShareLabel == nil)
        #expect(unrelated?.isScreenSharing == nil)

        let phone = CallEvidence.detect(app: .phone, buttons: ["End", "Mute", "Share Screen"])
        #expect(phone?.screenShareLabel == nil)
        #expect(phone?.isScreenSharing == nil)
    }

    @Test func unsupportedProcessesAreExcluded() {
        #expect(CallApp(bundleIdentifier: "com.example.chat") == nil)
        #expect(CallApp(bundleIdentifier: "com.google.Chrome") == nil)
        #expect(CallApp(bundleIdentifier: "com.apple.FaceTime") == .faceTime)
        #expect(CallApp(bundleIdentifier: "com.apple.mobilephone") == .phone)
        #expect(CallApp(bundleIdentifier: "com.microsoft.teams2") == .teams)
    }

    @Test func meetRequiresExactSecureOriginAndKnownControlHints() {
        #expect(CallEvidence.isMeetURL("https://meet.google.com/abc-defg-hij"))
        #expect(!CallEvidence.isMeetURL("https://meet.google.com.evil.example/abc"))
        #expect(!CallEvidence.isMeetURL("https://example.com/meet.google.com/abc"))
        #expect(!CallEvidence.isMeetURL("http://meet.google.com/abc"))
        #expect(!CallEvidence.isMeetURL("https://meet.google.com/"))
        let call = CallEvidence.detect(app: .googleMeet, buttons: ["Leave call", "Turn off microphone (⌘ + d)", "Turn on camera (⌘ + e)"])
        #expect(call?.isMuted == false)
        #expect(call?.isCameraOn == false)
    }

    @Test func revokingConnectionPreventsQueuedSideEffects() throws {
        let gate = CallAuthorizationGate()
        #expect(gate.currentToken() == nil)
        gate.renew()
        let token = try #require(gate.currentToken())
        var pressed = false
        #expect(gate.perform(token: token) { true })
        gate.invalidate()
        #expect(!gate.perform(token: token) { pressed = true; return true })
        #expect(!pressed)
        gate.renew()
        #expect(!gate.perform(token: token) { pressed = true; return true })
        #expect(!pressed)
    }

    @Test func checkedMuteCheckboxMeansUnmuteAction() {
        #expect(CallEvidence.checkboxAction(label: "Mute", checked: true) == "unmute")
        #expect(CallEvidence.checkboxAction(label: "Mute", checked: false) == "mute")
        #expect(CallEvidence.checkboxAction(label: "Notifications", checked: true) == nil)
    }
}
