import SwiftUI

/// What the floating window shows beside the transport controls when Expanded.
enum LiquidPlayerPanel: Equatable {
    case cover, queue, lyrics
    /// Lyrics drawn straight over the window (no box), with the controls on a soft scrim.
    case floatingLyrics

    var isLyrics: Bool { self == .lyrics || self == .floatingLyrics }
    /// The panel the Lyrics button opens, per the "Floating lyrics" setting.
    static func lyricsPanel(floating: Bool) -> LiquidPlayerPanel { floating ? .floatingLyrics : .lyrics }
}

/// The floating Liquid Player: one glass surface that morphs between Mini, Player and Expanded as
/// its height changes (the controller drives `height` from a two-finger vertical swipe).
struct LiquidPlayerView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var queue: PlayingNextModel = .shared
    @ObservedObject var outputs: AudioOutputModel = .shared
    var lyrics: LyricsModel = .shared
    var height: CGFloat
    var onClose: () -> Void = {}
    var onCycle: () -> Void = {}
    var onChoosePanel: (LiquidPlayerPanel) -> Void = { _ in }
    var panel: LiquidPlayerPanel = .cover
    @State private var hovered = false
    @State private var volume = SystemVolumeControl.read()?.level ?? 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: LiquidPlayerSize { LiquidPlayerPolicy.layout(forHeight: height) }
    private var width: CGFloat { LiquidPlayerPolicy.width(forHeight: height) }
    private var radius: CGFloat {
        let t = (LiquidPlayerPolicy.clamp(height) - LiquidPlayerPolicy.minHeight)
            / (LiquidPlayerPolicy.size(for: .player).height - LiquidPlayerPolicy.minHeight)
        return 29 + 7 * min(1, max(0, t))
    }

    var body: some View {
        ZStack {
            background
            Group {
                if let track = model.track {
                    content(track)
                        .id(layout)
                        .transition(.blurReplace)
                } else {
                    Text("Not Playing").font(IslandFont.title).foregroundStyle(IslandInk.secondary)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: layout)
            closeButton
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
        .onHover { hovered = $0 }
        .trackSwipe(stretch: .constant(0), model: model)
        .preferredColorScheme(.dark)
        .onAppear { queue.refresh(for: model.track) }
        .onChange(of: model.track?.songKey) { _, _ in queue.refresh(for: model.track) }
    }

    // MARK: Surface

    private var background: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.42)
            ArtworkGlow(image: model.track?.artwork, opacity: layout == .expanded ? 0.5 : 0.3)
        }
    }

    private var closeButton: some View {
        VStack { HStack {
            if hovered {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                        .frame(width: 18, height: 18).background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(IslandPressStyle(pressedScale: 0.85)).help("Return to the notch")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                Spacer()
            } else { Spacer() }
        }.padding(layout == .mini ? 4 : 8); Spacer() }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    @ViewBuilder
    private func content(_ track: NowPlayingTrack) -> some View {
        switch layout {
        case .mini: mini(track)
        case .player: player(track)
        case .expanded: expanded(track)
        }
    }

    // MARK: Mini

    private func mini(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 10) {
            PlayerArtwork(track: track, cornerRadius: 10).frame(width: 40, height: 40)
            PlayerTitleBlock(track: track, titleSize: 13, subtitleSize: 12, spacing: 1)
            PlaybackWaveform(isPlaying: track.isPlaying, colored: true, tint: ArtworkTint.color(for: track.artwork))
                .frame(width: 22, height: 20)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCycle)
    }

    // MARK: Player

    private func player(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                PlayerArtwork(track: track, cornerRadius: 12).frame(width: 52, height: 52)
                    .overlay(alignment: .bottomTrailing) { SourceBadgeIcon(source: track.snapshot.source).scaleEffect(0.8).offset(x: 4, y: 4) }
                PlayerTitleBlock(track: track, titleSize: 14, subtitleSize: 13)
                PlaybackWaveform(isPlaying: track.isPlaying, colored: true, tint: ArtworkTint.color(for: track.artwork))
                    .frame(width: 23, height: 20)
            }
            .contentShape(Rectangle()).onTapGesture(perform: onCycle)
            PlayerScrubber(track: track, seek: model.seek, barHeight: 5, textSize: 11)
            ZStack {
                PlayerTransport(track: track, model: model, glyph: 21, spacing: 50)
                HStack {
                    if QueueCapability.supportsQueue(track.snapshot.source) {
                        PlayerGlyphButton(symbol: "list.bullet", label: "Playing Next", size: 15, frame: 32) {
                            onChoosePanel(.queue)
                        }
                    }
                    Spacer()
                    outputMenu(compact: true)
                }
            }
            .frame(height: 38)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Expanded

    @ViewBuilder
    private func expanded(_ track: NowPlayingTrack) -> some View {
        if panel == .floatingLyrics { floatingLyrics(track) } else { expandedStack(track) }
    }

    /// Lyrics fill the window; the title row and controls sit on a bottom scrim.
    private func floatingLyrics(_ track: NowPlayingTrack) -> some View {
        let scale = width / 600
        return ZStack(alignment: .bottom) {
            LyricsView(model: lyrics, track: track, height: height / scale)
                .scaleEffect(scale).frame(width: width, height: height)
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .frame(height: 230).allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    PlayerArtwork(track: track, cornerRadius: 8).frame(width: 36, height: 36)
                    PlayerTitleBlock(track: track, titleSize: 14, subtitleSize: 12, spacing: 1)
                        .contentShape(Rectangle()).onTapGesture(perform: onCycle)
                }
                .padding(.horizontal, 20)
                PlayerScrubber(track: track, seek: model.seek, barHeight: 5, textSize: 11)
                    .padding(.horizontal, 20).padding(.top, 6)
                PlayerTransport(track: track, model: model, glyph: 24, spacing: 62).frame(height: 44)
                bottomRow(track).padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
    }

    private func expandedStack(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: 0) {
            stage(track).frame(height: 308).padding(.horizontal, 16).padding(.top, 16)
            HStack(alignment: .center, spacing: 8) {
                PlayerTitleBlock(track: track, titleSize: 17, subtitleSize: 14, spacing: 2)
                    .contentShape(Rectangle()).onTapGesture(perform: onCycle)
                if track.snapshot.isFavorite != nil {
                    PlayerGlyphButton(symbol: track.snapshot.isFavorite == true ? "star.fill" : "star",
                                      label: "Favorite", size: 15, frame: 30, bounce: true, action: model.toggleFavorite)
                }
            }
            .frame(height: 44).padding(.horizontal, 20).padding(.top, 8)
            PlayerScrubber(track: track, seek: model.seek, barHeight: 5, textSize: 11).padding(.horizontal, 20)
            PlayerTransport(track: track, model: model, glyph: 24, spacing: 62).frame(height: 44)
            volumeRow.padding(.horizontal, 22).padding(.top, 4)
            bottomRow(track).padding(.horizontal, 18).padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func stage(_ track: NowPlayingTrack) -> some View {
        switch panel {
        case .cover:
            PlayerArtwork(track: track, cornerRadius: 22)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        case .queue:
            PlayingNextColumn(queue: queue, track: track, topInset: 14).padding(.leading, -12)
        case .lyrics, .floatingLyrics:
            LyricsView(model: lyrics, track: track).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: max(4, proxy.size.width * volume))
                }
                .frame(height: 5).frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    volume = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                    _ = SystemVolumeControl.setLevel(volume)
                })
            }
            .frame(height: 20)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
        }
        .foregroundStyle(IslandInk.secondary)
        .accessibilityElement(children: .ignore).accessibilityLabel("Volume")
        .accessibilityValue("\(Int(volume * 100)) percent")
    }

    private func bottomRow(_ track: NowPlayingTrack) -> some View {
        HStack {
            if QueueCapability.supportsQueue(track.snapshot.source) {
                PlayerGlyphButton(symbol: "list.bullet", label: "Playing Next", size: 15, frame: 32, active: panel == .queue) {
                    onChoosePanel(panel == .queue ? .cover : .queue)
                }
            } else { Color.clear.frame(width: 32, height: 32) }
            if let mode = track.snapshot.repeatMode {
                PlayerGlyphButton(symbol: mode.symbol, label: mode.title, size: 15, frame: 32,
                                  active: mode.isActive, bounce: true, action: model.cycleRepeat)
            }
            Spacer()
            // Repeat and Add to Playlist take the room the device name needs.
            outputMenu(compact: track.snapshot.repeatMode != nil || track.snapshot.source == .music)
            Spacer()
            if track.snapshot.source == .music {
                MusicPlaylistMenu(playlists: .shared) {
                    Image(systemName: PlaylistFeedback.symbol(for: MusicPlaylistsModel.shared.outcome))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
            }
            if AppSettings.shared.lyricsEnabled {
                PlayerGlyphButton(symbol: panel.isLyrics ? "quote.bubble.fill" : "quote.bubble", label: "Lyrics",
                                  size: 15, frame: 32, active: panel.isLyrics) {
                    onChoosePanel(panel.isLyrics ? .cover
                                  : LiquidPlayerPanel.lyricsPanel(floating: AppSettings.shared.mediaFloatingLyrics))
                }
            } else { Color.clear.frame(width: 32, height: 32) }
        }
    }

    private func outputMenu(compact: Bool) -> some View {
        Menu {
            ForEach(outputs.devices) { device in
                Button { outputs.select(device) } label: {
                    Label(device.name, systemImage: outputs.selectedID == device.id ? "checkmark" : device.playerSymbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: outputs.selectedDevice?.playerSymbol ?? "laptopcomputer").font(.system(size: compact ? 16 : 13))
                if !compact {
                    Text(outputs.selectedDevice?.name ?? "Output").font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(0.9)).frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .onAppear { outputs.refresh() }
    }
}
