import SwiftUI

/// Interruptible springs tuned to the elastic compact/expanded transition shown in Apple’s demos.
/// These are Brim tuning values; Apple does not publish its animation constants.
enum NotchMotion {
    /// Scales a spring's duration by the Animation speed preset. Bounce is a ratio, so it stays.
    static func spring(duration: Double, bounce: Double, speed: ShellAnimationSpeed = AppSettings.shared.shellAnimationSpeed) -> Animation {
        .spring(duration: duration * speed.durationScale, bounce: bounce)
    }

    /// Spring in `response`/`dampingFraction` terms, with the speed preset applied (response / speed).
    static func spring(response: Double, damping: Double, speed: ShellAnimationSpeed = AppSettings.shared.shellAnimationSpeed) -> Animation {
        .spring(response: response * speed.durationScale, dampingFraction: damping)
    }

    /// Shell springs: open response 0.5 s, damping 0.625 (a slight overshoot);
    /// close response 0.40 s, critically damped. Reduce Motion swaps both for a 0.3 s critically damped spring.
    static func expansion(_ expanded: Bool, reduceMotion: Bool) -> Animation? {
        if reduceMotion { return .spring(response: 0.3, dampingFraction: 1) }
        return expanded ? spring(response: 0.5, damping: 0.625) : spring(response: 0.40, damping: 1)
    }

    /// State and layout changes inside the open island (response 0.5 s, damping 0.75).
    static func layout(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : spring(response: 0.5, damping: 0.75)
    }

    /// Hover highlights.
    static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : spring(duration: 0.2, bounce: 0)
    }

    /// Press-down and release of a control.
    static func press(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : spring(duration: 0.24, bounce: 0.4)
    }
}
