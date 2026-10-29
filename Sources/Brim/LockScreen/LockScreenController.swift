import AppKit
import CoreGraphics
import Foundation
import os
import SwiftUI

/// Side effects the state machine asks for. A protocol so tests observe them without a screen.
@MainActor
protocol LockScreenEffects: AnyObject {
    /// Returns false when the cards could not be shown (bridge missing).
    func presentCards() -> Bool
    func dismissCards(animated: Bool)
    /// Re-show the space and re-delegate the windows that are already up (display wake).
    func refreshCards()
    func playSound(_ name: String?)
    func flash(locked: Bool)
}

enum LockScreenAvailability: Equatable {
    case disabled
    /// SkyLight (or a symbol it needs) is missing; sounds and the notch animation still work.
    case notAvailableOnThisMac
    case ready
}

@MainActor
final class LockScreenController {
    static let shared = LockScreenController()
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "lockscreen")

    private let settings: AppSettings
    private let bridge: LockScreenWindowBridge
    private let effects: LockScreenEffects
    private(set) var machine = LockStateMachine()
    private(set) var cardsOnScreen = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var resyncTask: Task<Void, Never>?

    init(settings: AppSettings = .shared, bridge: LockScreenWindowBridge? = nil,
         effects: LockScreenEffects? = nil) {
        let bridge = bridge ?? SkyLightBridge()
        self.settings = settings
        self.bridge = bridge
        self.effects = effects ?? LiveLockScreenEffects(bridge: bridge)
    }

    var availability: LockScreenAvailability {
        guard settings.lockScreenEnabled else { return .disabled }
        return bridge.isAvailable ? .ready : .notAvailableOnThisMac
    }

    /// Settings copy for the current availability.
    var availabilityNote: String? {
        availability == .notAvailableOnThisMac ? "Not available on this macOS" : nil
    }

    // MARK: Lifecycle

    /// Call at launch and whenever the lock-screen settings change.
    func settingsChanged() {
        if settings.lockScreenEnabled { startObserving() } else { stopObserving() }
    }

    func start() { settingsChanged() }

    private func startObserving() {
        guard observers.isEmpty else { return }
        machine.reset(locked: Self.sessionIsLocked())
        let distributed = DistributedNotificationCenter.default()
        let names: [(String, LockEvent)] = [
            ("com.apple.screenIsLocked", .locked), ("com.apple.screenIsUnlocked", .unlocked),
            ("com.apple.sessionagent.screenIsLocked", .locked),
            ("com.apple.sessionagent.screenIsUnlocked", .unlocked),
            ("com.apple.screensaver.didstart", .screensaverStarted),
            ("com.apple.screensaver.didstop", .screensaverStopped),
        ]
        for (name, event) in names {
            let token = distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handle(event) }
            }
            observers.append((distributed, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleResync() }
            }))
        }
        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleResync() }
        }
        observers.append((NotificationCenter.default, screens))
        Self.log.notice("lock-screen monitoring started (locked now: \(self.machine.isLocked), skylight: \(self.bridge.isAvailable))")
        if machine.isLocked { handle(.locked, announce: false) }
    }

    /// The lock screen comes up a moment after the display wakes, and a lock that happened while the
    /// display was asleep may not have reached us; check now and once more after it settles.
    private func scheduleResync() {
        resync()
        resyncTask?.cancel()
        resyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.resync()
        }
    }

    /// Brings the state machine and the windows back in line with the real session state.
    func resync(sessionLocked: Bool? = nil) {
        guard settings.lockScreenEnabled else { return }
        let locked = sessionLocked ?? Self.sessionIsLocked()
        let action = LockResync.action(
            machineLocked: machine.isLocked, sessionLocked: locked,
            cardsWanted: machine.cardsVisible(keepDuringScreensaver: settings.lockScreenDuringScreensaver),
            cardsOnScreen: cardsOnScreen)
        if action != .none { Self.log.notice("lock-screen resync: \(String(describing: action), privacy: .public)") }
        switch action {
        case .none: break
        case .lock: handle(.locked, announce: false)
        case .unlock: handle(.unlocked, announce: false)
        case .present: perform(.presentCards, announce: false)
        case .refreshWindows: effects.refreshCards()
        }
    }

    private func stopObserving() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        resyncTask?.cancel()
        resyncTask = nil
        if cardsOnScreen { effects.dismissCards(animated: false) }
        cardsOnScreen = false
        machine = LockStateMachine()
    }

    // MARK: Events

    func handle(_ event: LockEvent, announce: Bool = true) {
        guard settings.lockScreenEnabled else { return }
        let effectsToRun = machine.handle(event, keepDuringScreensaver: settings.lockScreenDuringScreensaver)
        Self.log.notice("lock event \(String(describing: event), privacy: .public) -> \(String(describing: effectsToRun), privacy: .public)")
        updateKeepAwake(for: event)
        for effect in effectsToRun { perform(effect, announce: announce) }
    }

    private func perform(_ effect: LockEffect, announce: Bool) {
        switch effect {
        case .presentCards:
            guard availability == .ready else {
                Self.log.error("lock-screen cards skipped: SkyLight unavailable")
                return
            }
            cardsOnScreen = effects.presentCards()
        case .dismissCards(let animated):
            guard cardsOnScreen else { return }
            effects.dismissCards(animated: animated)
            cardsOnScreen = false
        case .playLockSound:
            if announce { effects.playSound(settings.lockScreenLockSound) }
        case .playUnlockSound:
            if announce { effects.playSound(settings.lockScreenUnlockSound) }
        case .flashLocked:
            if announce && settings.lockScreenNotchAnimation { effects.flash(locked: true) }
        case .flashUnlocked:
            if announce && settings.lockScreenNotchAnimation { effects.flash(locked: false) }
        }
    }

    private func updateKeepAwake(for event: LockEvent) {
        switch event {
        case .locked: LockKeepAwake.shared.locked(minutes: settings.lockScreenKeepAwakeMinutes)
        case .unlocked: LockKeepAwake.shared.unlocked()
        default: break
        }
    }

    /// `CGSSessionScreenIsLocked` is set in the session dictionary while the screen is locked.
    static func sessionIsLocked() -> Bool {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (dictionary?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

@MainActor
final class LiveLockScreenEffects: LockScreenEffects {
    private let presenter: LockScreenPresenter
    private var morph: Task<Void, Never>?

    init(bridge: LockScreenWindowBridge) {
        self.bridge = bridge
        presenter = LockScreenPresenter(bridge: bridge)
    }

    private let bridge: LockScreenWindowBridge

    func presentCards() -> Bool {
        EdgeSliderController.shared.lockBridge = bridge
        return presenter.present()
    }
    func dismissCards(animated: Bool) {
        EdgeSliderController.shared.lockBridge = nil
        presenter.dismiss(animated: animated)
    }
    func refreshCards() { presenter.resync() }
    func playSound(_ name: String?) { LockScreenSounds.play(name) }

    /// A padlock that closes on lock and opens on unlock: the flash starts on the opposite glyph and
    /// swaps to the final one, which the island animates as a symbol replace.
    func flash(locked: Bool) {
        morph?.cancel()
        let flashes = IslandFlashCenter.shared
        let start = locked ? "lock.open.fill" : "lock.fill"
        let end = locked ? "lock.fill" : "lock.open.fill"
        let title = locked ? "Locked" : "Unlocked"
        flashes.show(title, symbol: start, tint: .white, duration: 1.8)
        morph = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            flashes.show(title, symbol: end, tint: locked ? .white : .green, duration: 1.6)
        }
    }
}
