import SwiftUI

/// Everything a card needs to know to draw, as plain values so the views render without live models.
struct LockMediaInfo {
    let track: NowPlayingTrack
}

struct LockTimerInfo: Equatable {
    let title: String
    let symbol: String
    let tint: Color
    let duration: TimeInterval
    let endDate: Date?
    let pausedRemaining: TimeInterval?
    var canControl = true

    func remaining(at date: Date) -> TimeInterval {
        max(0, min(duration, pausedRemaining ?? endDate?.timeIntervalSince(date) ?? 0))
    }
    var isPaused: Bool { pausedRemaining != nil }
}

struct LockAwakeInfo: Equatable {
    let until: Date?
}

struct LockCardsContent {
    var media: LockMediaInfo?
    var timer: LockTimerInfo?
    var awake: LockAwakeInfo?
}

struct LockCardActions {
    var previous: () -> Void = {}
    var playPause: () -> Void = {}
    var next: () -> Void = {}
    var toggleTimer: () -> Void = {}
    var stopAwake: () -> Void = {}
    /// Tap on the artwork: opens the fullscreen artwork scene.
    var openArtwork: (() -> Void)?
    /// Scrubber release: seek to this many seconds. nil hides the drag affordance.
    var seek: ((TimeInterval) -> Void)?
}

/// Maps a point on the scrubber to a playback position.
enum LockScrubMath {
    static func position(x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval? {
        guard width > 0, duration > 0, x.isFinite else { return nil }
        return duration * Double(min(1, max(0, x / width)))
    }
}

/// Card surface: Liquid is frosted glass with a light edge; Dark is a near-black slab.
struct LockCardBackground: View {
    let look: LockScreenLook
    var radius: CGFloat = 28
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            switch look {
            case .liquid where reduceTransparency:
                shape.fill(Color(white: GlassTokens.of(.panel).solid))
                if let tint { shape.fill(tint.opacity(0.12)) }
            case .liquid:
                shape.fill(.ultraThinMaterial)
                // The readability tint every glass surface shares (`GlassStyle`), so white text holds
                // its contrast over a bright wallpaper.
                shape.fill(Color.black.opacity(GlassTokens.of(.panel).tintedVeil * 0.6))
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let tint { shape.fill(tint.opacity(0.16)).blendMode(.plusLighter) }
            case .dark:
                shape.fill(Color(white: 0.07, opacity: 0.88))
                if let tint { shape.fill(tint.opacity(0.10)) }
            }
        }
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(look == .liquid ? 0.55 : 0.22), .white.opacity(0.06), .white.opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        .compositingGroup()
    }
}

/// A round control with a soft fill, used for transport and timer buttons.
struct LockRoundButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 40
    var prominent = false
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(prominent ? tint : tint.opacity(0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.9))
        .accessibilityLabel(label)
    }
}

enum LockTimeFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
