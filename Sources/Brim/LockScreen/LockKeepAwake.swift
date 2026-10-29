import Foundation
import IOKit.pwr_mgt

/// Holds a "prevent display sleep" assertion for N minutes after the screen locks (so the lock-screen
/// cards stay visible), and releases it when the window ends or the Mac is unlocked.
@MainActor
final class LockKeepAwake {
    static let shared = LockKeepAwake()
    private(set) var policy = LockKeepAwakePolicy()
    private var assertion: IOPMAssertionID = 0
    private var expiry: Timer?
    var isHolding: Bool { assertion != 0 }

    func locked(minutes: Int, now: Date = .now) {
        policy.locked(at: now)
        guard policy.shouldHold(minutes: minutes, now: now) else { return }
        release()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Brim lock screen keep awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertion = id
        expiry = Timer.scheduledTimer(withTimeInterval: policy.remaining(minutes: minutes, now: now), repeats: false) {
            [weak self] _ in Task { @MainActor in self?.release() }
        }
    }

    func unlocked() {
        policy.unlocked()
        release()
    }

    private func release() {
        expiry?.invalidate()
        expiry = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
    }
}
