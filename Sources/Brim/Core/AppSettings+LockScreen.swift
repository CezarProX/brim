// AppSettings+LockScreen.swift
// Brim
//
// Typed preferences for the lock-screen cards. The master toggle is ON by default, so a stock install
// shows the player. If the
// private window-server API it needs is missing, the cards switch themselves off.

import Foundation

/// How the lock-screen cards are painted.
enum LockScreenLook: String, CaseIterable, Identifiable {
    case liquid, dark
    var id: String { rawValue }
    var title: String { self == .liquid ? "Liquid" : "Dark" }
}

extension AppSettings {
    private enum LockKey {
        static let enabled = "lockScreenEnabled"
        static let mediaCard = "lockScreenMediaCard"
        static let timerCard = "lockScreenTimerCard"
        static let awakeCard = "lockScreenAwakeCard"
        static let statusRow = "lockScreenStatusRow"
        static let lockSound = "lockScreenLockSound"
        static let unlockSound = "lockScreenUnlockSound"
        static let notchAnimation = "lockScreenNotchAnimation"
        static let duringScreensaver = "lockScreenDuringScreensaver"
        static let look = "lockScreenLook"
        static let hideAfterPausedMinutes = "lockScreenHideAfterPausedMinutes"
    }

    private func lockFlag(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    /// Master switch. On by default; the user can turn it off.
    var lockScreenEnabled: Bool {
        get { lockFlag(LockKey.enabled, default: true) }
        set { defaults.set(newValue, forKey: LockKey.enabled) }
    }
    var lockScreenMediaCard: Bool {
        get { lockFlag(LockKey.mediaCard, default: true) }
        set { defaults.set(newValue, forKey: LockKey.mediaCard) }
    }
    var lockScreenTimerCard: Bool {
        get { lockFlag(LockKey.timerCard, default: true) }
        set { defaults.set(newValue, forKey: LockKey.timerCard) }
    }
    var lockScreenAwakeCard: Bool {
        get { lockFlag(LockKey.awakeCard, default: true) }
        set { defaults.set(newValue, forKey: LockKey.awakeCard) }
    }
    var lockScreenStatusRow: Bool {
        get { lockFlag(LockKey.statusRow, default: true) }
        set { defaults.set(newValue, forKey: LockKey.statusRow) }
    }
    /// Play the notch padlock animation when the screen locks and unlocks.
    var lockScreenNotchAnimation: Bool {
        get { lockFlag(LockKey.notchAnimation, default: true) }
        set { defaults.set(newValue, forKey: LockKey.notchAnimation) }
    }
    var lockScreenDuringScreensaver: Bool {
        get { lockFlag(LockKey.duringScreensaver, default: false) }
        set { defaults.set(newValue, forKey: LockKey.duringScreensaver) }
    }
    var lockScreenLook: LockScreenLook {
        get { defaults.string(forKey: LockKey.look).flatMap(LockScreenLook.init(rawValue:)) ?? .liquid }
        set { defaults.set(newValue.rawValue, forKey: LockKey.look) }
    }
    /// Minutes a paused song stays on the lock screen. 0 hides it as soon as it pauses.
    var lockScreenHideAfterPausedMinutes: Int {
        get {
            let stored = defaults.object(forKey: LockKey.hideAfterPausedMinutes) as? Int ?? 5
            return min(60, max(0, stored))
        }
        set { defaults.set(min(60, max(0, newValue)), forKey: LockKey.hideAfterPausedMinutes) }
    }

    /// A system sound name from `LockScreenSounds.available()`, or nil for no sound.
    var lockScreenLockSound: String? {
        get { LockScreenSounds.validated(defaults.string(forKey: LockKey.lockSound)) }
        set { defaults.set(LockScreenSounds.validated(newValue) ?? LockScreenSounds.none, forKey: LockKey.lockSound) }
    }
    var lockScreenUnlockSound: String? {
        get { LockScreenSounds.validated(defaults.string(forKey: LockKey.unlockSound)) }
        set { defaults.set(LockScreenSounds.validated(newValue) ?? LockScreenSounds.none, forKey: LockKey.unlockSound) }
    }
}
