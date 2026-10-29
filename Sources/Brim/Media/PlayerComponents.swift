import SwiftUI

/// Pieces shared by the notch player card and the floating Liquid Player.

/// Stable identity of the displayed song, for crossfades and queue reloads.
extension NowPlayingTrack {
    var songKey: String { "\(snapshot.source.rawValue)\u{1F}\(title)\u{1F}\(artist)" }
}

/// Cover art that crossfades (with a touch of blur) when the song changes.
struct PlayerArtwork: View {
    let track: NowPlayingTrack
    var cornerRadius: CGFloat = 12
    /// Slow Ken Burns drift; when off, the cover stays perfectly still.
    var drift = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MusicArtworkView(image: track.artwork, cornerRadius: cornerRadius)
                .id(track.songKey + (track.artwork == nil ? "·" : "#"))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .kenBurns(active: drift && track.isPlaying && !track.isTransitioning, seed: track.songKey)
        .overlay { if track.isTransitioning { SkeletonShimmer(cornerRadius: cornerRadius) } }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.38), value: track.songKey)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: track.artwork == nil)
        .accessibilityHidden(true)
    }
}

/// The placeholder drawn over cover and text while a next/previous is in flight.
struct SkeletonShimmer: View {
    var cornerRadius: CGFloat = 8
    @State private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(bright ? 0.26 : 0.12))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

/// Title and artist; both swap with a blur crossfade and turn into skeleton bars while skipping.
struct PlayerTitleBlock: View {
    let track: NowPlayingTrack
    var titleSize: CGFloat = 13.5
    var subtitleSize: CGFloat = 13
    var spacing: CGFloat = 2
    var onOpenTrack: (() -> Void)?
    var onOpenArtist: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if track.isTransitioning {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)).frame(width: 96, height: titleSize)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(width: 64, height: subtitleSize - 2)
            } else {
                navigationButton(onOpenTrack, label: "Open current song") {
                  HStack(spacing: 5) {
                    MarqueeText(text: track.title, font: .system(size: titleSize, weight: .semibold),
                                color: IslandInk.primary, tracking: -0.1)
                    LyricsBadge(size: max(11, titleSize * 0.8))
                  }
                }
                navigationButton(track.artist.isEmpty ? nil : onOpenArtist, label: "Open artist") {
                  MarqueeText(text: track.artist.isEmpty ? track.sourceName : track.artist,
                              font: .system(size: subtitleSize), color: IslandInk.secondary)
                }
            }
        }
        .id(track.isTransitioning ? "skeleton" : track.songKey)
        .transition(.blurReplace)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: track.songKey)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: track.isTransitioning)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func navigationButton<Content: View>(
        _ action: (() -> Void)?, label: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        if let action {
            Button(action: action, label: content).buttonStyle(.plain).accessibilityLabel(label)
        } else {
            content()
        }
    }

}

/// "1:09 ━━━━━━ -1:24". Position comes from the elapsed-time clock, not from polling.
struct PlayerScrubber: View {
    let track: NowPlayingTrack
    let seek: (TimeInterval, NowPlayingSnapshot) -> Void
    var barHeight: CGFloat = 6
    var textSize: CGFloat = 12
    var tint: Color = Color.white.opacity(0.88)
    @State private var preview: TimeInterval?
    @State private var dragTrack: NowPlayingSnapshot?
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !track.isPlaying)) { context in
            let position = preview ?? track.position(at: context.date)
            let fraction = track.duration > 0 ? min(1, max(0, position / track.duration)) : 0
            HStack(spacing: 8) {
                Text(Self.time(position)).frame(width: 34, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(tint).frame(width: max(barHeight, proxy.size.width * fraction))
                    }
                    .frame(height: hovered || preview != nil ? barHeight + 3 : barHeight)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(drag(width: proxy.size.width))
                }
                .frame(height: 20)
                Text("-" + Self.time(max(0, track.duration - position))).frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
            .foregroundStyle(IslandInk.secondary)
            .onHover { hovered = $0 }
            .animation(NotchMotion.press(reduceMotion: reduceMotion), value: hovered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Self.time(position)) of \(Self.time(track.duration))")
            .accessibilityAdjustableAction { direction in
                seek(min(track.duration, max(0, position + (direction == .increment ? 5 : -5))), track.snapshot)
            }
        }
        .opacity(track.duration > 0 ? 1 : 0.35)
        .disabled(track.duration <= 0)
        .onDisappear { preview = nil; dragTrack = nil }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragTrack == nil { dragTrack = track.snapshot }
                preview = PlaybackTimeline.position(x: value.location.x, width: width, duration: track.duration)
            }
            .onEnded { value in
                defer { preview = nil; dragTrack = nil }
                guard let expected = dragTrack,
                      let target = PlaybackTimeline.position(x: value.location.x, width: width, duration: expected.duration)
                else { return }
                seek(target, expected)
            }
    }

    static func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(max(0, seconds.isFinite ? seconds : 0), 604_800))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// A glyph button with a springy press and symbol morph; no chrome.
struct PlayerGlyphButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 20
    var frame: CGFloat = 44
    /// nil = a plain button; true / false = a toggle that is on / off.
    var active: Bool?
    var dimmed = false
    var bounce = false
    /// Secondary glyphs rest dimmer (list / output buttons) and light up on hover.
    var quiet = false
    let action: () -> Void
    @State private var hovered = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glyphColor: Color {
        if dimmed { return .white.opacity(0.5) }
        if active == true { return Color(red: 0.45, green: 0.68, blue: 1) }
        if hovered { return .white }
        return .white.opacity(active == false || quiet ? 0.62 : 0.94)
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(glyphColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, options: .speed(1.5), value: bounce ? taps : 0)
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.88))
        .onHover { hovered = $0 }
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: active)
        .help(label).accessibilityLabel(label)
    }
}

/// prev / play-pause / next. Never disabled while a command is in flight: taps apply at once.
struct PlayerTransport: View {
    let track: NowPlayingTrack
    @ObservedObject var model: NowPlayingModel
    var glyph: CGFloat = 21
    var buttonFrame: CGFloat = 44
    var spacing: CGFloat = 54

    var body: some View {
        HStack(spacing: spacing - glyph - 20) {
            PlayerGlyphButton(symbol: "backward.fill", label: "Previous track", size: glyph, frame: buttonFrame, bounce: true,
                              action: model.previous)
            PlayerGlyphButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                              label: track.isPlaying ? "Pause" : "Play", size: glyph + 4, frame: buttonFrame, action: model.playPause)
            PlayerGlyphButton(symbol: "forward.fill", label: "Next track", size: glyph, frame: buttonFrame, bounce: true,
                              action: model.next)
        }
    }
}

/// Dominant-colour glow behind a player, fading out from the artwork's accent.
struct ArtworkGlow: View {
    let image: NSImage?
    var opacity: Double = 0.4

    var body: some View {
        let tint = ArtworkTint.color(for: image) ?? .clear
        RadialGradient(colors: [tint.opacity(opacity), tint.opacity(0)], center: .top, startRadius: 0, endRadius: 360)
            .blendMode(.plusLighter)
            .animation(.easeInOut(duration: 0.5), value: image.map(ObjectIdentifier.init))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension AudioOutputDevice {
    /// The built-in speakers read as the laptop, as in the output button.
    var playerSymbol: String {
        let lowered = name.lowercased()
        let builtIn = lowered.contains("macbook") || lowered.contains("built-in") || lowered.contains("mac mini")
            || lowered.contains("imac") || lowered.contains("mac studio")
        return builtIn && icon == "speaker.wave.2.fill" ? "laptopcomputer" : icon
    }
}
