import Foundation

/// "Keep the screen awake N minutes after locking": the display stays on for the window after a lock,
/// then the assertion is released and macOS sleeps the display on its own schedule.
struct LockKeepAwakePolicy: Equatable {
    private(set) var lockedAt: Date?

    mutating func locked(at date: Date) { lockedAt = date }
    mutating func unlocked() { lockedAt = nil }

    func shouldHold(minutes: Int, now: Date) -> Bool {
        guard minutes > 0, let lockedAt else { return false }
        return now.timeIntervalSince(lockedAt) < TimeInterval(minutes * 60)
    }

    func remaining(minutes: Int, now: Date) -> TimeInterval {
        guard let lockedAt else { return 0 }
        return max(0, TimeInterval(minutes * 60) - now.timeIntervalSince(lockedAt))
    }
}
