import AppKit
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct IslandOpeningTests {
    @Test func islandStartsVisibleAndOpensOnHover() async throws {
        let screen = try #require(NSScreen.screens.first)
        var pointer = CGPoint(x: screen.frame.minX + 20, y: screen.frame.minY + 40)
        let controller = NotchShelfController(pointerLocation: { pointer })
        controller.start()
        defer { controller.stop() }
        let presentation = try #require(controller.presentation(onScreen: screen.frame))
        let panel = try #require(NSApp.windows.first {
            $0 is IslandPanel && $0.frame == presentation.geometry.hostingFrame
        })
        try await Task.sleep(for: .milliseconds(150))
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)

        pointer = CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        try await Task.sleep(for: .milliseconds(450))
        #expect(presentation.isExpanded)
    }

    @Test func explicitOpenRecoversHiddenIslandAndStaysOpen() async throws {
        let screen = try #require(NSScreen.screens.first)
        let id = try #require(ShellEnvironment.displayID(of: screen))
        let uuid = try #require(ShellEnvironment.displayUUID(id))
        let settings = AppSettings.shared
        let keys = ["notchShelfEnabled", AppSettings.ShellKey.externalVisibility,
                    AppSettings.ShellExtraKey.disabledDisplays]
        let previous = keys.map { settings.defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { settings.defaults.set(value, forKey: key) }
                else { settings.defaults.removeObject(forKey: key) }
            }
        }
        settings.notchShelfEnabled = false
        settings.shellExternalVisibility = .never
        settings.shellDisabledDisplays = [uuid, "another-display"]
        let controller = NotchShelfController(pointerLocation: {
            CGPoint(x: screen.frame.minX + 20, y: screen.frame.minY + 40)
        })
        defer { controller.stop() }

        controller.showIsland()
        let presentation = try #require(controller.presentation(onScreen: screen.frame))
        try await Task.sleep(for: .milliseconds(450))
        #expect(settings.notchShelfEnabled)
        #expect(settings.shellDisabledDisplays == ["another-display"])
        #expect(settings.shellExternalVisibility == .never)
        #expect(presentation.isExpanded)
        let panel = try #require(NSApp.windows.first {
            $0 is IslandPanel && $0.frame == presentation.geometry.hostingFrame
        })
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        #expect((panel.contentView?.bounds.width ?? 0) > 0)

        controller.showIsland()
        #expect(presentation.isExpanded)
    }

    @Test func clipboardStaysOpenUntilThePointerVisitsAndLeaves() async throws {
        let screen = try #require(NSScreen.screens.first)
        let away = CGPoint(x: screen.frame.minX + 20, y: screen.frame.minY + 40)
        var pointer = away
        let controller = NotchShelfController(pointerLocation: { pointer })
        controller.start()
        defer { controller.stop() }
        let presentation = try #require(controller.presentation(onScreen: screen.frame))

        controller.presentClipboard()
        try await Task.sleep(for: .milliseconds(450))
        #expect(presentation.isExpanded)
        #expect(presentation.isShowingLibrary)

        pointer = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 5)
        try await Task.sleep(for: .milliseconds(100))
        pointer = away
        try await Task.sleep(for: .milliseconds(450))
        #expect(!presentation.isExpanded)
    }
}

@MainActor
struct FirstLaunchIslandTests {
    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "brim.first-island.\(UUID().uuidString)")!)
    }

    @Test func finishingIntroductionRevealsRealIslandWithoutPermissionChecks() {
        let preferences = settings()
        var reveals = 0
        let controller = OnboardingWindowController(settings: preferences,
            revealIsland: { reveals += 1 }, startIslandTour: { _ in })
        controller.handle(.close)
        #expect(preferences.onboardingCompleted)
        #expect(reveals == 1)
        controller.handle(.close)
        #expect(reveals == 1)
    }

    @Test func replayingIntroductionDoesNotEnableAnIntentionallyDisabledIsland() {
        let preferences = settings()
        preferences.onboardingCompleted = true
        preferences.notchShelfEnabled = false
        let controller = OnboardingWindowController(settings: preferences,
            revealIsland: { Issue.record("Replay must respect a disabled island") }, startIslandTour: { _ in })
        controller.handle(.close)
        #expect(!preferences.notchShelfEnabled)
    }

    @Test func newInstallRemainsVisibleOverFullscreen() {
        let preferences = settings()
        let context = ShellVisibilityContext(isExternalDisplay: true,
            externalMode: preferences.shellExternalVisibility,
            hideOnFullscreen: preferences.shellHideOnFullscreen,
            displayHasFullscreenWindow: true)
        #expect(ShellVisibilityPolicy.decide(context) == .visible)
        preferences.shellHideOnFullscreen = true
        #expect(preferences.shellHideOnFullscreen)
    }
}
