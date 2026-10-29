import Foundation

/// What the system tells us about the session.
enum LockEvent: Equatable {
    case locked, unlocked, screensaverStarted, screensaverStopped
}

/// What the controller should do in response. Pure data, so the policy is testable.
enum LockEffect: Equatable {
    case presentCards
    case dismissCards(animated: Bool)
    case playLockSound
    case playUnlockSound
    case flashLocked
    case flashUnlocked
}

/// Lock and screensaver state. macOS posts several notifications for one lock
/// (`screenIsLocked` and the session agent's twin), so repeats must be no-ops.
struct LockStateMachine: Equatable {
    private(set) var isLocked = false
    private(set) var screensaverActive = false

    /// Whether the cards should be on screen right now.
    func cardsVisible(keepDuringScreensaver: Bool) -> Bool {
        if screensaverActive { return keepDuringScreensaver }
        return isLocked
    }

    mutating func handle(_ event: LockEvent, keepDuringScreensaver: Bool) -> [LockEffect] {
        let wasVisible = cardsVisible(keepDuringScreensaver: keepDuringScreensaver)
        let wasLocked = isLocked
        switch event {
        case .locked: isLocked = true
        case .unlocked:
            isLocked = false
            // Unlocking ends any screensaver that was covering the lock screen.
            screensaverActive = false
        case .screensaverStarted: screensaverActive = true
        case .screensaverStopped: screensaverActive = false
        }
        var effects: [LockEffect] = []
        if isLocked != wasLocked {
            effects += isLocked ? [.playLockSound, .flashLocked] : [.playUnlockSound, .flashUnlocked]
        }
        let visible = cardsVisible(keepDuringScreensaver: keepDuringScreensaver)
        if visible != wasVisible {
            // Unlocking runs the system's own transition; cards fading on top of it linger over the
            // desktop, so they go at once. A screensaver starting still fades them.
            effects.append(visible ? .presentCards : .dismissCards(animated: event != .unlocked))
        }
        return effects
    }

    /// Sync after the feature is switched on while the Mac is already locked.
    mutating func reset(locked: Bool) {
        isLocked = locked
        screensaverActive = false
    }
}

/// What to do when we re-read the session state (display wake, screen change), because a lock or
/// unlock notification can be missed while the display is asleep.
enum LockResyncAction: Equatable {
    case none, lock, unlock, present, refreshWindows
}

enum LockResync {
    static func action(machineLocked: Bool, sessionLocked: Bool, cardsWanted: Bool, cardsOnScreen: Bool)
        -> LockResyncAction {
        if sessionLocked != machineLocked { return sessionLocked ? .lock : .unlock }
        guard sessionLocked, cardsWanted else { return .none }
        return cardsOnScreen ? .refreshWindows : .present
    }
}
