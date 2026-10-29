import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Brim

/// Records every SkyLight call instead of talking to the window server.
final class RecordingSkyLightAPI: SkyLightSpaceAPI {
    var calls: [String] = []
    var nextSpace: Int32 = 42
    /// What `spaces(connection:windows:)` answers; nil models a missing lookup symbol.
    var spacesAnswer: [Int]? = []

    func mainConnection() -> Int32 { calls.append("main"); return 7 }
    func createSpace(connection: Int32) -> Int32 { calls.append("create(\(connection))"); return nextSpace }
    func setAbsoluteLevel(connection: Int32, space: Int32, level: Int32) { calls.append("level(\(space),\(level))") }
    func showSpaces(connection: Int32, _ spaces: [Int32]) { calls.append("show(\(spaces))") }
    func hideSpaces(connection: Int32, _ spaces: [Int32]) { calls.append("hide(\(spaces))") }
    func addWindows(connection: Int32, space: Int32, windows: [Int]) -> Bool {
        calls.append("add(\(space),\(windows.count))")
        return true
    }
    func spaces(connection: Int32, windows: [Int]) -> [Int]? { spacesAnswer }
    func destroySpace(connection: Int32, space: Int32) { calls.append("destroy(\(space))") }
}

private func freshSettings() -> AppSettings {
    let suite = "lockscreen.skylight.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return AppSettings(defaults: defaults)
}

@MainActor
private func orderedWindow() -> NSWindow {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 2, height: 2), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
}

// MARK: Bridge

@MainActor
@Suite(.serialized)
struct LockScreenSkyLightBridgeTests {
    @Test func missingSkyLightMeansUnavailableAndNoCalls() {
        let bridge = SkyLightBridge(api: nil)
        #expect(!bridge.isAvailable)
        let window = orderedWindow()
        defer { window.close() }
        #expect(!bridge.delegate(window))
        #expect(bridge.isDelegated(window) == nil)
    }

    @Test func spaceIsCreatedLazilyAtTheLockScreenLevelThenReused() {
        let api = RecordingSkyLightAPI()
        let bridge = SkyLightBridge(api: api)
        #expect(bridge.isAvailable)
        #expect(api.calls.isEmpty, "launching must not touch the window server")
        let window = orderedWindow()
        defer { window.close() }
        #expect(bridge.delegate(window))
        #expect(api.calls == ["main", "create(7)", "level(42,400)", "show([42])", "add(42,1)"])
        #expect(bridge.delegate(window))
        #expect(api.calls.suffix(1) == ["add(42,1)"])
        #expect(api.calls.filter { $0.hasPrefix("create") }.count == 1)
    }

    @Test func failedSpaceCreationRefusesToDelegate() {
        let api = RecordingSkyLightAPI()
        api.nextSpace = 0
        let bridge = SkyLightBridge(api: api)
        let window = orderedWindow()
        defer { window.close() }
        #expect(!bridge.delegate(window))
        #expect(!api.calls.contains { $0.hasPrefix("add") })
    }

    @Test func isDelegatedReadsTheOverlaySpace() {
        let api = RecordingSkyLightAPI()
        let bridge = SkyLightBridge(api: api)
        let window = orderedWindow()
        defer { window.close() }
        #expect(bridge.isDelegated(window) == nil, "no space yet")
        _ = bridge.delegate(window)
        api.spacesAnswer = [42]
        #expect(bridge.isDelegated(window) == true)
        api.spacesAnswer = [4]
        #expect(bridge.isDelegated(window) == false)
        api.spacesAnswer = nil
        #expect(bridge.isDelegated(window) == nil)
    }

    @Test func reassertAndTeardown() {
        let api = RecordingSkyLightAPI()
        let bridge = SkyLightBridge(api: api)
        bridge.reassert()
        #expect(api.calls.isEmpty, "nothing to reassert before the space exists")
        let window = orderedWindow()
        defer { window.close() }
        _ = bridge.delegate(window)
        api.calls.removeAll()
        bridge.reassert()
        #expect(api.calls == ["level(42,400)", "show([42])"])
        api.calls.removeAll()
        bridge.teardown()
        #expect(api.calls == ["hide([42])", "destroy(42)"])
        #expect(bridge.space == 0)
    }

    /// Mask 7 never lists our own overlay space (checked against the real window server on
    /// macOS 27), which made the watchdog re-delegate every window every tick.
    @Test func liveMasksMatchWhatTheWindowServerAccepts() {
        #expect(LiveSkyLightAPI.addWindowsMask == 7)
        #expect(LiveSkyLightAPI.spaceLookupMask & 0x8 != 0)
        #expect(SkyLightBridge.notificationCenterAtScreenLockLevel == 400)
    }

    @Test func skyLightResolvesOnThisMac() {
        #expect(LiveSkyLightAPI.load() != nil)
    }
}

// MARK: Resync (display wake, missed notifications)

struct LockResyncTests {
    @Test(arguments: [
        // machineLocked, sessionLocked, cardsWanted, cardsOnScreen, expected
        (false, true, false, false, LockResyncAction.lock),
        (true, false, true, true, .unlock),
        (true, true, true, true, .refreshWindows),
        (true, true, true, false, .present),
        (true, true, false, false, .none),
        (false, false, false, false, .none),
    ])
    func decision(_ row: (Bool, Bool, Bool, Bool, LockResyncAction)) {
        #expect(LockResync.action(machineLocked: row.0, sessionLocked: row.1, cardsWanted: row.2,
                                  cardsOnScreen: row.3) == row.4)
    }
}

@MainActor
struct LockScreenControllerResyncTests {
    private func make() -> (LockScreenController, FakeLockEffects) {
        let settings = freshSettings()
        let effects = FakeLockEffects()
        return (LockScreenController(settings: settings, bridge: FakeLockBridge(), effects: effects), effects)
    }

    @Test func lockMissedWhileAsleepPresentsSilentlyOnWake() {
        let (controller, effects) = make()
        controller.resync(sessionLocked: true)
        #expect(effects.log == ["present"])
        #expect(controller.cardsOnScreen)
    }

    @Test func wakeOnLockScreenRefreshesTheWindows() {
        let (controller, effects) = make()
        controller.handle(.locked)
        effects.log.removeAll()
        controller.resync(sessionLocked: true)
        #expect(effects.log == ["refresh"])
    }

    @Test func unlockMissedWhileAsleepDismisses() {
        let (controller, effects) = make()
        controller.handle(.locked)
        effects.log.removeAll()
        controller.resync(sessionLocked: false)
        #expect(effects.log == ["dismiss(false)"])
        #expect(!controller.cardsOnScreen)
    }

    @Test func failedPresentIsRetriedOnWake() {
        let (controller, effects) = make()
        effects.presentSucceeds = false
        controller.handle(.locked)
        #expect(!controller.cardsOnScreen)
        effects.presentSucceeds = true
        controller.resync(sessionLocked: true)
        #expect(controller.cardsOnScreen)
    }

    @Test func disabledControllerIgnoresResync() {
        let settings = freshSettings()
        settings.lockScreenEnabled = false
        let effects = FakeLockEffects()
        let controller = LockScreenController(settings: settings, bridge: FakeLockBridge(), effects: effects)
        controller.resync(sessionLocked: true)
        #expect(effects.log.isEmpty)
    }
}

// MARK: Scrubber and hit testing

struct LockScrubMathTests {
    @Test func mapsAndClamps() {
        #expect(LockScrubMath.position(x: 50, width: 200, duration: 240) == 60)
        #expect(LockScrubMath.position(x: -10, width: 200, duration: 240) == 0)
        #expect(LockScrubMath.position(x: 500, width: 200, duration: 240) == 240)
        #expect(LockScrubMath.position(x: 50, width: 0, duration: 240) == nil)
        #expect(LockScrubMath.position(x: 50, width: 200, duration: 0) == nil)
        #expect(LockScrubMath.position(x: .nan, width: 200, duration: 240) == nil)
    }
}

@MainActor
struct LockScreenPanelInputTests {
    /// The panel never becomes key, so the hosting view must take the first click itself.
    @Test func panelTakesClicksWithoutBecomingKey() {
        let panel = LockScreenPanel(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        defer { panel.close() }
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.canBecomeVisibleWithoutLogin)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.ignoresMouseEvents)
        let host = LockScreenHostingView(rootView: AnyView(EmptyView()))
        #expect(host.acceptsFirstMouse(for: nil))
    }

    @Test func resyncReassertsTheSpaceAndRedelegates() throws {
        try #require(!NSScreen.screens.isEmpty, "needs a display")
        let bridge = FakeLockBridge()
        let registry = LockStatusRegistry(providers: [BatteryStatusProvider(reader: { .init(percent: 50, externalPower: false) })])
        let model = LockScreenViewModel(settings: freshSettings(), registry: registry)
        let presenter = LockScreenPresenter(bridge: bridge, viewModel: model)
        presenter.resync()
        #expect(bridge.reasserted == 0, "nothing to resync before presenting")
        #expect(presenter.present())
        defer { presenter.teardown() }
        let before = bridge.delegated
        presenter.tick()
        #expect(bridge.delegated == before, "a healthy panel is not re-delegated every tick")
        presenter.resync()
        #expect(bridge.reasserted == 1)
        #expect(bridge.delegated > before)
    }
}
