import SwiftUI

/// Fullscreen artwork scene opened by tapping the artwork on the lock-screen media card: the cover
/// huge in the middle over a blurred, artwork-tinted dim of itself, the clock on top, title and
/// transport below and a close button in the corner.
struct LockScreenArtworkScene: View {
    let info: LockMediaInfo
    let actions: LockCardActions
    var now: Date?
    var close: () -> Void = {}

    private var track: NowPlayingTrack { info.track }
    private var accent: Color { ArtworkTint.color(for: track.artwork) ?? .pink }

    var body: some View {
        GeometryReader { proxy in
            let cover = min(proxy.size.height * 0.46, proxy.size.width * 0.42)
            ZStack {
                background.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                VStack(spacing: 0) {
                    clock.padding(.top, proxy.size.height * 0.05)
                    Spacer(minLength: 16)
                    artwork(size: cover)
                    Spacer(minLength: 28)
                    titleBlock
                    controls.padding(.top, 18)
                    Spacer(minLength: proxy.size.height * 0.08)
                }
                .frame(maxWidth: min(560, proxy.size.width - 48), maxHeight: .infinity)
                closeButton.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        ZStack {
            Color.black
            if let image = track.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 60).saturation(1.2).scaleEffect(1.3)
            } else {
                LinearGradient(colors: [accent, .black], startPoint: .top, endPoint: .bottom)
            }
            accent.opacity(0.28).blendMode(.plusLighter)
            LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = now ?? context.date
            HStack(spacing: 10) {
                Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let image = track.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: "music.note").font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(.white.opacity(0.85)) }
            }
        }
        .kenBurns(active: track.isPlaying && track.artwork != nil, seed: track.songKey)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: size * 0.06, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.55), radius: 40, y: 22)
        .scaleEffect(track.isPlaying ? 1 : 0.9)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: track.isPlaying)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(track.title).font(.system(size: 24, weight: .bold)).lineLimit(1)
            Text(track.artist.isEmpty ? track.album : track.artist)
                .font(.system(size: 17, weight: .medium)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 38) {
            LockRoundButton(symbol: "backward.fill", label: "Previous", size: 52, action: actions.previous)
            LockRoundButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                            label: track.isPlaying ? "Pause" : "Play", size: 64, prominent: true, action: actions.playPause)
            LockRoundButton(symbol: "forward.fill", label: "Next", size: 52, action: actions.next)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32).background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.9))
        .accessibilityLabel("Close artwork")
        .padding(18)
    }
}
