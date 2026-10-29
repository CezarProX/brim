import SwiftUI

struct LockMediaCard: View {
    let info: LockMediaInfo
    let look: LockScreenLook
    let actions: LockCardActions

    private var track: NowPlayingTrack { info.track }
    private var accent: Color { ArtworkTint.color(for: track.artwork) ?? .pink }

    /// The island's player, piece for piece (`MusicPlayerCard`): cover with title and artist beside
    /// it and the live waveform on the right, one scrubber row with both times, the transport centred.
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                PlayerTitleBlock(track: track, titleSize: 15, subtitleSize: 13.5)
                Spacer(minLength: 8)
                AutomixWaveformSlot(track: track, tint: accent).frame(width: 23, height: 16)
            }
            .frame(height: 66)
            PlayerScrubber(track: track, seek: { position, _ in actions.seek?(position) })
            HStack(spacing: 34) {
                PlayerGlyphButton(symbol: "backward.fill", label: "Previous", size: 21, bounce: true, action: actions.previous)
                PlayerGlyphButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                                  label: track.isPlaying ? "Pause" : "Play", size: 25, action: actions.playPause)
                PlayerGlyphButton(symbol: "forward.fill", label: "Next", size: 21, bounce: true, action: actions.next)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: LockScreenLayout.cardWidth, height: LockCardKind.nowPlaying.height)
        .background { LockIslandSlab() }
    }

    private var artwork: some View {
        PlayerArtwork(track: track, cornerRadius: 12.5, drift: false)
            .frame(width: 66, height: 66)
            .contentShape(RoundedRectangle(cornerRadius: 12.5, style: .continuous))
            .onTapGesture { actions.openArtwork?() }
            .accessibilityAddTraits(actions.openArtwork == nil ? [] : .isButton)
            .accessibilityLabel("Artwork")
    }
}

/// The island's own glass on the lock screen: the wallpaper blurred under a dark veil, a faint top
/// sheen and a hairline rim catching the light, the same look as the open Dynamic Island.
struct LockIslandSlab: View {
    var radius: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            IslandGlassMaterial()
            Color.black.opacity(0.55)
            LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .top, endPoint: .center)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
