import AppKit
import Testing

@testable import Brim

@MainActor
struct OnboardingStartupTests {
    @Test func introductionFollowsActiveSpaceAndCanAppearOverFullscreen() {
        let window = OnboardingWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 500),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.hidesOnDeactivate)
    }

    @Test func explicitReopenResumesUnfinishedIntroduction() {
        for launcher in ["com.apple.finder", "com.apple.dock", "com.apple.Spotlight"] {
            #expect(ReopenPolicy.destination(sender: launcher, onboardingCompleted: false) == .introduction)
            #expect(ReopenPolicy.destination(sender: launcher, onboardingCompleted: true) == .settings)
        }
    }

    @Test func backgroundServicesDoNotReopenIntroduction() {
        for sender in [nil, "com.apple.Siri", "com.apple.intelligenceplatformd"] {
            #expect(ReopenPolicy.destination(sender: sender, onboardingCompleted: false) == nil)
        }
    }
}
