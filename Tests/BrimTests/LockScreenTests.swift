import AppKit
import Foundation
import Testing

@testable import Brim

// MARK: Fakes

@MainActor
final class FakeLockBridge: LockScreenWindowBridge {
    var isAvailable: Bool
    var delegated = 0
    var delegatedState: Bool? = true
    var tornDown = false
    init(available: Bool = true) { isAvailable = available }
    func delegate(_ window: NSWindow) -> Bool { delegated += 1; return isAvailable }
    func isDelegated(_ window: NSWindow) -> Bool? { delegatedState }
    var reasserted = 0
    func reassert() { reasserted += 1 }
    func teardown() { tornDown = true }
}

@MainActor
final class FakeLockEffects: LockScreenEffects {
    var log: [String] = []
    var presentSucceeds = true
    func presentCards() -> Bool { log.append("present"); return presentSucceeds }
    func dismissCards(animated: Bool) { log.append("dismiss(\(animated))") }
    func refreshCards() { log.append("refresh") }
    func playSound(_ name: String?) { log.append("sound:\(name ?? "none")") }
    func flash(locked: Bool) { log.append(locked ? "flash:lock" : "flash:unlock") }
}

private func freshSettings() -> AppSettings {
    let suite = "lockscreen.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return AppSettings(defaults: defaults)
}

// MARK: State machine

struct LockStateMachineTests {
    @Test func lockShowsCardsAndAnnounces() {
        var machine = LockStateMachine()
        let effects = machine.handle(.locked, keepDuringScreensaver: false)
        #expect(effects == [.playLockSound, .flashLocked, .presentCards])
        #expect(machine.isLocked)
    }

    @Test func unlockHidesAtOnceAndAnnounces() {
        var machine = LockStateMachine()
        _ = machine.handle(.locked, keepDuringScreensaver: false)
        let effects = machine.handle(.unlocked, keepDuringScreensaver: false)
        #expect(effects == [.playUnlockSound, .flashUnlocked, .dismissCards(animated: false)])
    }

    @Test func duplicateNotificationsAreNoOps() {
        var machine = LockStateMachine()
        _ = machine.handle(.locked, keepDuringScreensaver: false)
        #expect(machine.handle(.locked, keepDuringScreensaver: false).isEmpty)
        _ = machine.handle(.unlocked, keepDuringScreensaver: false)
        #expect(machine.handle(.unlocked, keepDuringScreensaver: false).isEmpty)
    }

    @Test func screensaverOverLockedScreenHidesCardsUnlessKept() {
        var machine = LockStateMachine()
        _ = machine.handle(.locked, keepDuringScreensaver: false)
        #expect(machine.handle(.screensaverStarted, keepDuringScreensaver: false) == [.dismissCards(animated: true)])
        #expect(machine.handle(.screensaverStopped, keepDuringScreensaver: false) == [.presentCards])
    }

    @Test func keepVisibleDuringScreensaverLeavesCardsUp() {
        var machine = LockStateMachine()
        _ = machine.handle(.locked, keepDuringScreensaver: true)
        #expect(machine.handle(.screensaverStarted, keepDuringScreensaver: true).isEmpty)
        #expect(machine.handle(.screensaverStopped, keepDuringScreensaver: true).isEmpty)
    }

    @Test func screensaverAloneShowsCardsOnlyWhenKept() {
        var plain = LockStateMachine()
        #expect(plain.handle(.screensaverStarted, keepDuringScreensaver: false).isEmpty)
        var kept = LockStateMachine()
        #expect(kept.handle(.screensaverStarted, keepDuringScreensaver: true) == [.presentCards])
        #expect(kept.handle(.screensaverStopped, keepDuringScreensaver: true) == [.dismissCards(animated: true)])
    }

    @Test func unlockEndsScreensaverCover() {
        var machine = LockStateMachine()
        _ = machine.handle(.locked, keepDuringScreensaver: true)
        _ = machine.handle(.screensaverStarted, keepDuringScreensaver: true)
        let effects = machine.handle(.unlocked, keepDuringScreensaver: true)
        #expect(effects.contains(.dismissCards(animated: false)))
        #expect(!machine.screensaverActive)
    }
}

// MARK: Layout

struct LockScreenLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private func inputs(media: Bool = true, timer: Bool = true, awake: Bool = true) -> LockCardInputs {
        LockCardInputs(hasMedia: media, timerActive: timer, awakeActive: awake)
    }

    @Test func stacksMediaOverAwakeOverTimer() {
        let layout = LockScreenLayout.plan(inputs(), screen: screen)
        #expect(layout.cards.map(\.kind) == [.nowPlaying, .awake, .timer])
        let frames = layout.cards.map(\.frame)
        #expect(frames[0].minY > frames[1].minY && frames[1].minY > frames[2].minY)
        #expect(abs(frames[2].maxY + LockScreenLayout.spacing - frames[1].minY) < 0.5)
    }

    @Test func cardsSitAboveTheLoginAreaAndAreCentered() {
        let layout = LockScreenLayout.plan(inputs(), screen: screen)
        let frame = try! #require(layout.cardsFrame)
        #expect(frame.minY >= screen.height * LockScreenLayout.loginClearance - 0.5)
        #expect(abs(frame.midX - screen.midX) < 0.5)
    }

    @Test func disabledOrIdleCardsAreOmitted() {
        var wanted = inputs()
        wanted.timerEnabled = false
        #expect(LockScreenLayout.plan(wanted, screen: screen).cards.map(\.kind) == [.nowPlaying, .awake])
        #expect(LockScreenLayout.plan(inputs(media: false, timer: false, awake: false), screen: screen).cards.isEmpty)
    }

    @Test func shortScreenDropsLowestPriorityCardsFirst() {
        let short = CGRect(x: 0, y: 0, width: 1024, height: 520)
        let kinds = LockScreenLayout.plan(inputs(), screen: short).cards.map(\.kind)
        #expect(kinds.first == .nowPlaying)
        #expect(!kinds.contains(.timer) || kinds.count == 3)
        #expect(kinds.count < 3)
    }

    @Test func statusRowNeedsItemsAndSitsUnderTheClock() {
        var wanted = inputs()
        #expect(LockScreenLayout.plan(wanted, screen: screen).statusRow == nil)
        wanted.statusItemCount = 2
        let row = try! #require(LockScreenLayout.plan(wanted, screen: screen).statusRow)
        #expect(row.minY > screen.midY)
        wanted.statusRowEnabled = false
        #expect(LockScreenLayout.plan(wanted, screen: screen).statusRow == nil)
    }

    @Test func narrowScreenShrinksCards() {
        let narrow = CGRect(x: 0, y: 0, width: 360, height: 800)
        let frame = try! #require(LockScreenLayout.plan(inputs(), screen: narrow).cardsFrame)
        #expect(frame.width <= 360 - LockScreenLayout.margin * 2)
    }

    @Test func pausedSongHidesAfterTheConfiguredTime() {
        #expect(LockMediaVisibility.shouldShow(hasTrack: true, isPlaying: true, pausedFor: nil, hideAfterMinutes: 5))
        #expect(LockMediaVisibility.shouldShow(hasTrack: true, isPlaying: false, pausedFor: 120, hideAfterMinutes: 5))
        #expect(!LockMediaVisibility.shouldShow(hasTrack: true, isPlaying: false, pausedFor: 301, hideAfterMinutes: 5))
        #expect(!LockMediaVisibility.shouldShow(hasTrack: true, isPlaying: false, pausedFor: 1, hideAfterMinutes: 0))
        #expect(!LockMediaVisibility.shouldShow(hasTrack: false, isPlaying: true, pausedFor: nil, hideAfterMinutes: 5))
    }
}

// MARK: Sounds and settings

struct LockScreenSoundTests {
    @Test func systemSoundsAreListedAndValidated() throws {
        let available = LockScreenSounds.available()
        try #require(!available.isEmpty)
        let name = available[0]
        #expect(LockScreenSounds.validated(name) == name)
        #expect(LockScreenSounds.validated("None") == nil)
        #expect(LockScreenSounds.validated("../../etc/passwd") == nil)
        #expect(LockScreenSounds.validated("NoSuchSound") == nil)
    }

    @Test func selectionPersistsAcrossReopen() throws {
        let suite = "lockscreen.sounds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let name = try #require(LockScreenSounds.available().first)
        let settings = AppSettings(defaults: defaults)
        settings.lockScreenLockSound = name
        settings.lockScreenUnlockSound = nil
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.lockScreenLockSound == name)
        #expect(reopened.lockScreenUnlockSound == nil)
    }

    @Test func tamperedStoredNameFallsBackToNone() {
        let settings = freshSettings()
        settings.defaults.set("/tmp/evil", forKey: "lockScreenLockSound")
        #expect(settings.lockScreenLockSound == nil)
    }

    /// On by default: a stock install shows the player on the lock screen.
    @Test func defaultsAreOnAndSafe() {
        let settings = freshSettings()
        #expect(settings.lockScreenEnabled)
        #expect(settings.lockScreenMediaCard && settings.lockScreenTimerCard && settings.lockScreenAwakeCard)
        #expect(settings.lockScreenLook == .liquid)
        #expect(settings.lockScreenHideAfterPausedMinutes == 5)
        settings.lockScreenHideAfterPausedMinutes = 999
        #expect(settings.lockScreenHideAfterPausedMinutes == 60)
    }
}

// MARK: Controller

@MainActor
struct LockScreenControllerTests {
    private func make(available: Bool = true, enabled: Bool = true)
        -> (LockScreenController, FakeLockEffects, AppSettings) {
        let settings = freshSettings()
        settings.lockScreenEnabled = enabled
        let effects = FakeLockEffects()
        let controller = LockScreenController(
            settings: settings, bridge: FakeLockBridge(available: available), effects: effects)
        return (controller, effects, settings)
    }

    @Test func lockThenUnlockRunsTheFullSequence() {
        let (controller, effects, _) = make()
        controller.handle(.locked)
        controller.handle(.unlocked)
        #expect(effects.log == ["sound:none", "flash:lock", "present", "sound:none", "flash:unlock", "dismiss(false)"])
    }

    @Test func bridgeUnavailableSkipsCardsButKeepsSoundAndFlash() {
        let (controller, effects, _) = make(available: false)
        #expect(controller.availability == .notAvailableOnThisMac)
        #expect(controller.availabilityNote == "Not available on this macOS")
        controller.handle(.locked)
        controller.handle(.unlocked)
        #expect(!effects.log.contains("present"))
        #expect(!effects.log.contains("dismiss(true)"))
        #expect(effects.log.contains("flash:lock") && effects.log.contains("flash:unlock"))
    }

    @Test func disabledMasterToggleDoesNothing() {
        let (controller, effects, _) = make(enabled: false)
        #expect(controller.availability == .disabled)
        controller.handle(.locked)
        #expect(effects.log.isEmpty)
    }

    @Test func animationToggleSuppressesFlashOnly() {
        let (controller, effects, settings) = make()
        settings.lockScreenNotchAnimation = false
        controller.handle(.locked)
        #expect(effects.log.contains("present") && !effects.log.contains("flash:lock"))
    }

    @Test func failedPresentDoesNotTriggerADismiss() {
        let (controller, effects, _) = make()
        effects.presentSucceeds = false
        controller.handle(.locked)
        controller.handle(.unlocked)
        #expect(!effects.log.contains("dismiss(true)"))
    }

    @Test func screensaverStartHidesCardsWhileLocked() {
        let (controller, effects, _) = make()
        controller.handle(.locked)
        controller.handle(.screensaverStarted)
        #expect(effects.log.last == "dismiss(true)")
        controller.handle(.screensaverStopped)
        #expect(effects.log.last == "present")
    }
}

// MARK: Status providers

@MainActor
struct LockStatusProviderTests {
    private struct Fixed: LockStatusProvider {
        let id: String
        let count: Int
        func items(now: Date) -> [LockStatusItem] {
            (0..<count).map { LockStatusItem(id: "\(id)\($0)", symbol: "sun.max", title: "t", detail: "d", tint: .white) }
        }
    }

    @Test func registryMergesCapsAndReplacesById() {
        let registry = LockStatusRegistry(providers: [Fixed(id: "a", count: 3)])
        registry.register(Fixed(id: "weather", count: 3))
        #expect(registry.items().count == LockStatusRegistry.maxItems)
        registry.register(Fixed(id: "a", count: 1))
        #expect(registry.providers.count == 2)
    }

    @Test func batteryTileReflectsChargingAndLow() {
        let charging = BatteryStatusProvider(reader: { .init(percent: 80, externalPower: true) })
        #expect(charging.items(now: .now).first?.detail == "Charging")
        let low = BatteryStatusProvider(reader: { .init(percent: 12, externalPower: false) })
        #expect(low.items(now: .now).first?.tint == .red)
        let none = BatteryStatusProvider(reader: { nil })
        #expect(none.items(now: .now).isEmpty)
    }

    @Test func calendarTileHidesFinishedEvents() {
        let now = Date()
        let past = CalendarMeeting(id: "1", title: "Old", startsAt: now - 7200, endsAt: now - 3600, calendar: "c", joinURL: nil)
        let next = CalendarMeeting(id: "2", title: "Standup", startsAt: now + 600, endsAt: now + 1800, calendar: "c", joinURL: nil)
        #expect(CalendarStatusProvider(meeting: { past }).items(now: now).isEmpty)
        #expect(CalendarStatusProvider(meeting: { next }).items(now: now).first?.title == "Standup")
    }
}

// MARK: Presenter

@MainActor
struct LockScreenPresenterTests {
    @Test func unavailableBridgeRefusesToPresent() {
        let presenter = LockScreenPresenter(bridge: FakeLockBridge(available: false))
        #expect(!presenter.present())
        #expect(!presenter.isPresented)
    }

    @Test func watchdogRedelegatesWhenSpaceIsLost() throws {
        try #require(!NSScreen.screens.isEmpty, "needs a display")
        let bridge = FakeLockBridge()
        let registry = LockStatusRegistry(providers: [BatteryStatusProvider(reader: { .init(percent: 50, externalPower: false) })])
        let settings = freshSettings()
        let model = LockScreenViewModel(settings: settings, registry: registry)
        let presenter = LockScreenPresenter(bridge: bridge, viewModel: model)
        #expect(presenter.present())
        defer { presenter.teardown() }
        let delegatedOnPresent = bridge.delegated
        #expect(delegatedOnPresent > 0)
        presenter.tick()
        #expect(presenter.redelegations == 0)
        bridge.delegatedState = false
        presenter.tick()
        #expect(presenter.redelegations >= 1)
        presenter.dismiss(animated: false)
        #expect(!presenter.isPresented)
        #expect(bridge.tornDown == false)
        presenter.teardown()
        #expect(bridge.tornDown)
    }
}
