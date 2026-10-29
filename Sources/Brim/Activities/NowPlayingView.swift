import SwiftUI

@MainActor
struct NowPlayingView: View {
    @ObservedObject var model: NowPlayingModel
    var embedded = false
    @ObservedObject var outputs: AudioOutputModel = .shared
    @ObservedObject var lyrics: LyricsModel = .shared
    var onOutputDrawerChange: (Bool) -> Void = { _ in }
    @State private var localShowingOutputs = false
    /// The drawer shows lyrics instead of the output list.
    @State private var drawerShowsLyrics = false
    @State private var swipeStretch: CGFloat = 0
    @State private var autoExpandedKey: String?
    private var outputDrawer: Binding<Bool>?
    private var showingOutputs: Bool { outputDrawer?.wrappedValue ?? localShowingOutputs }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NowPlayingModel, embedded: Bool = false, outputs: AudioOutputModel? = nil,
         lyrics: LyricsModel? = nil, showingLyrics: Bool = false,
         showingOutputs: Bool = false, outputDrawer: Binding<Bool>? = nil,
         onOutputDrawerChange: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.embedded = embedded
        self.outputs = outputs ?? .shared
        self.lyrics = lyrics ?? .shared
        self._drawerShowsLyrics = State(initialValue: showingLyrics)
        self._localShowingOutputs = State(initialValue: showingOutputs || showingLyrics)
        self.outputDrawer = outputDrawer
        self.onOutputDrawerChange = onOutputDrawerChange
    }

    var body: some View {
        Group {
            if let track = model.track { player(track) }
            else if let last = model.lastPlayed { resumePlayer(last) }
            else { emptyState.padding(embedded ? 0 : 16) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(.dark)
        .onChange(of: showingOutputs) { _, visible in
            onOutputDrawerChange(visible)
            if !visible { drawerShowsLyrics = false }
        }
        .onChange(of: lyrics.state) { _, _ in autoExpandLyricsIfNeeded() }
        .onDisappear { onOutputDrawerChange(false) }
    }

    private func player(_ track: NowPlayingTrack) -> some View {
        let trackKey = "\(track.title)\u{1F}\(track.artist)"
        return playerShell(trackKey: trackKey) {
            albumArtwork(track.artwork, animating: track.isPlaying && !track.isTransitioning, key: trackKey)
                .modifier(ElasticStretch(stretch: swipeStretch / 0.7, reduceMotion: reduceMotion))
                .id(trackKey)
                .transition(.blurReplace.combined(with: .scale(0.9)))
                .popOutHandle()
                .opacity(track.isTransitioning ? 0.45 : 1)
                .animation(.easeOut(duration: 0.15), value: track.isTransitioning)
                .position(x: 93.5, y: 72.5)
            SourceBadge(source: track.snapshot.source)
                .frame(width: 30, height: 30)
                .position(x: 128, y: 107)
            Button(action: model.openSource) {
                trackLabel(title: track.title, subtitle: track.artist.isEmpty ? track.sourceName : track.artist)
                    .id(trackKey)
                    .transition(.blurReplace)
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.98))
            .help(model.commandError.map { "\($0)\nOpen \(track.sourceName)" } ?? "Open \(track.sourceName)")
            .position(x: 336.5, y: 72.5)
            MusicActivityWaveform(isPlaying: track.isPlaying, tint: ArtworkTint.color(for: track.artwork))
                .frame(width: 27, height: 26).position(x: 536.5, y: 72.5)
            if track.duration > 0 {
                PlaybackTimeline(track: track, isBusy: model.isBusy, seek: model.seek)
                    .frame(width: 500, height: 32).position(x: 300, y: 136)
            }
            MusicTransportButton(symbol: "backward.fill", label: "Previous track", disabled: model.isBusy,
                                 action: model.previous).position(x: 198, y: 202)
            MusicTransportButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                                 label: track.isPlaying ? "Pause" : "Play", prominent: true,
                                 disabled: model.isBusy, action: model.playPause).position(x: 300, y: 202)
            MusicTransportButton(symbol: "forward.fill", label: "Next track", disabled: model.isBusy,
                                 action: model.next).position(x: 402, y: 202)
            extraButtons(track.snapshot)
        }
        .trackSwipe(stretch: $swipeStretch, model: model)
    }

    /// The configurable buttons left and right of the transport row.
    @ViewBuilder
    private func extraButtons(_ snapshot: NowPlayingSnapshot) -> some View {
        let settings = AppSettings.shared
        let caps = MediaButtonSlots.Capabilities(snapshot: snapshot, lyricsEnabled: settings.lyricsEnabled)
        let left = MediaButtonSlots.resolve(settings.mediaLeftButtons, capabilities: caps)
        let right = MediaButtonSlots.resolve(settings.mediaRightButtons, capabilities: caps)
        ForEach(Array(left.enumerated()), id: \.element) { index, kind in
            extraButton(kind, snapshot: snapshot)
                .position(x: MediaButtonSlots.centers(count: left.count, left: true)[index], y: 202)
        }
        ForEach(Array(right.enumerated()), id: \.element) { index, kind in
            extraButton(kind, snapshot: snapshot)
                .position(x: MediaButtonSlots.centers(count: right.count, left: false)[index], y: 202)
        }
    }

    @ViewBuilder
    private func extraButton(_ kind: MediaButtonKind, snapshot: NowPlayingSnapshot) -> some View {
        switch kind {
        case .output: outputButton
        case .lyrics: lyricsButton
        case .repeat: MusicRepeatSlotButton(mode: snapshot.repeatMode ?? .off, disabled: model.isBusy, action: model.cycleRepeat)
        case .addToPlaylist: MusicPlaylistSlotButton(disabled: model.isBusy)
        default:
            MusicSideButton(kind: kind, snapshot: snapshot, disabled: model.isBusy,
                            favorite: model.toggleFavorite, shuffle: model.toggleShuffle)
        }
    }

    /// The last song after its player quit, in the same layout as the live player so the
    /// island never switches designs; Play resumes it at the saved second.
    private func resumePlayer(_ last: NowPlayingResume.LastPlayed) -> some View {
        let trackKey = "\(last.title)\u{1F}\(last.artist)"
        return playerShell(trackKey: trackKey) {
            resumeArtwork(last)
                .id(trackKey)
                .transition(.blurReplace.combined(with: .scale(0.9)))
                .position(x: 93.5, y: 72.5)
            SourceBadge(source: last.source)
                .frame(width: 30, height: 30)
                .position(x: 128, y: 107)
            Button(action: model.resume) {
                trackLabel(title: last.title, subtitle: last.artist.isEmpty ? last.source.name : last.artist)
                    .id(trackKey)
                    .transition(.blurReplace)
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.98))
            .help("Recently played · resume in \(last.source.name) at \(time(last.position))")
            .position(x: 336.5, y: 72.5)
            MusicActivityWaveform(isPlaying: false, tint: ArtworkTint.color(for: model.lastArtwork))
                .frame(width: 27, height: 26).position(x: 536.5, y: 72.5)
            if last.duration > 0 {
                SavedPositionTimeline(position: last.position, duration: last.duration)
                    .frame(width: 500, height: 32).position(x: 300, y: 136)
            }
            // The player has quit, so only Play (resume) can act; skip buttons stay as dimmed placeholders.
            MusicTransportButton(symbol: "backward.fill", label: "Previous track", disabled: true,
                                 action: {}).position(x: 198, y: 202)
            // Plays like the Mac's play key; flips at once while macOS starts the song.
            MusicTransportButton(symbol: model.isStartingPlayback ? "pause.fill" : "play.fill",
                                 label: model.isStartingPlayback ? "Pause" : "Resume \(last.title)", prominent: true,
                                 action: model.resume).position(x: 300, y: 202)
            MusicTransportButton(symbol: "forward.fill", label: "Next track", disabled: true,
                                 action: {}).position(x: 402, y: 202)
            outputButton.position(x: 510, y: 202)
        }
    }

    private func trackLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                MarqueeText(text: title, font: .system(size: 25, weight: .semibold),
                            color: IslandInk.primary, tracking: -0.4)
                LyricsBadge(lyrics: lyrics, size: 20)
            }
            MarqueeText(text: subtitle, font: .system(size: 20), color: IslandInk.secondary)
        }
        .frame(width: 345, height: 64, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// All positions follow the reference's 600-point-wide shell, including hardware clearance.
    private func playerShell<Content: View>(trackKey: String, @ViewBuilder content: () -> Content) -> some View {
        let drawerStart = MusicPlayerLayout.height
        let totalHeight = drawerStart + (showingOutputs ? MusicPlayerLayout.drawerHeight : 0)
        let content = content()
        return GeometryReader { geometry in
            let scale = geometry.size.width / 600
            ZStack(alignment: .topLeading) {
                content
                if showingOutputs {
                    Capsule().fill(IslandFill.raised).frame(width: 96, height: 2)
                        .position(x: 300, y: drawerStart - 5).accessibilityHidden(true)
                        .transition(.opacity)
                    drawerContent.frame(width: 600, height: MusicPlayerLayout.drawerHeight)
                        .position(x: 300, y: drawerStart + MusicPlayerLayout.drawerHeight / 2)
                        .transition(.islandDrop)
                }
            }
            .font(.system(size: 15, weight: .medium)).monospacedDigit()
            .foregroundStyle(IslandInk.tertiary)
            .frame(width: 600, height: totalHeight, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: trackKey)
        }
        // Only width determines the player scale. A changing aspect ratio fits the whole
        // open drawer into the still-collapsed height, making every control shrink/jump.
        .accessibilityElement(children: .contain)
    }

    private func albumArtwork(_ image: NSImage?, animating: Bool = false, key: String = "") -> some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { MusicArtworkView(image: nil, cornerRadius: 14) }
        }
        .kenBurns(active: animating && image != nil, seed: key)
        .frame(width: 87, height: 87)
        .background(Color(red: 0.15, green: 0.18, blue: 0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func resumeArtwork(_ last: NowPlayingResume.LastPlayed) -> some View {
        if let image = model.lastArtwork { albumArtwork(image) }
        else if let raw = last.artworkURL, let url = NowPlayingSnapshot.safeArtworkURL(raw) {
            // Size first, then clip: a 16:9 video thumbnail becomes its square cover.
            AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                placeholder: { MusicArtworkView(image: nil, cornerRadius: 14) }
                .frame(width: 87, height: 87)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
        } else { albumArtwork(nil) }
    }

    @ViewBuilder
    private var drawerContent: some View {
        if drawerShowsLyrics, let track = model.track { LyricsView(model: lyrics, track: track) }
        else { outputDrawerContent }
    }

    private func setDrawer(open: Bool) {
        if let outputDrawer { outputDrawer.wrappedValue = open } else { localShowingOutputs = open }
    }

    /// Opens, closes or switches the shared drawer between the output list and lyrics.
    private func toggleDrawer(lyricsMode: Bool) {
        if !lyricsMode, !(showingOutputs && !drawerShowsLyrics) { outputs.refresh() }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
            if showingOutputs, drawerShowsLyrics != lyricsMode { drawerShowsLyrics = lyricsMode }
            else {
                drawerShowsLyrics = lyricsMode
                setDrawer(open: !showingOutputs)
            }
        }
    }

    private func autoExpandLyricsIfNeeded() {
        guard AppSettings.shared.lyricsEnabled, AppSettings.shared.lyricsAutoExpand,
              case .ready = lyrics.state, let track = model.track else { return }
        let key = "\(track.title)\u{1F}\(track.artist)"
        guard autoExpandedKey != key, !showingOutputs else { return }
        autoExpandedKey = key
        toggleDrawer(lyricsMode: true)
    }

    private var lyricsButton: some View {
        let open = showingOutputs && drawerShowsLyrics
        return OutputRouteButton(symbol: open ? "quote.bubble.fill" : "quote.bubble", open: open) {
            toggleDrawer(lyricsMode: true)
        }
        .help(open ? "Hide lyrics" : "Show lyrics")
        .accessibilityLabel("Lyrics")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }

    private var outputButton: some View {
        let selected = outputs.selectedDevice
        let open = showingOutputs && !drawerShowsLyrics
        return OutputRouteButton(symbol: selected?.icon ?? "airplay.audio", open: open) {
            toggleDrawer(lyricsMode: false)
        }
        .help(selected.map { "Audio output: \($0.name)" } ?? "Choose audio output")
        .accessibilityLabel("Choose audio output")
        .accessibilityValue("\(selected?.name ?? "Unknown output"), \(open ? "Expanded" : "Collapsed")")
    }

    private var outputDrawerContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(outputs.devices) { device in
                    OutputDeviceRow(name: device.name, symbol: device.icon,
                                    selected: outputs.selectedID == device.id) { outputs.select(device) }
                        .disabled(outputs.isBusy)
                }
                if outputs.isBusy && outputs.devices.isEmpty {
                    ProgressView().controlSize(.small).frame(height: 62)
                } else if outputs.devices.isEmpty {
                    Text(outputs.errorMessage ?? "No audio outputs found")
                        .font(.system(size: 18)).foregroundStyle(IslandInk.secondary)
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                if let error = outputs.errorMessage, !outputs.devices.isEmpty {
                    Text(error).font(.system(size: 16)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .padding(.horizontal, 31).padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: IslandSpace.m) {
                MusicArtworkView(image: nil, cornerRadius: 12).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not Playing").font(IslandFont.title).foregroundStyle(IslandInk.primary)
                    Text("Apple Music · Spotify · YouTube Music")
                        .font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
                }
            }
            // Embedded on Home, the idle line only repeats the heading; keep actionable states.
            if !model.status.isEmpty && !(embedded && model.status == NowPlayingModel.idleStatus) {
                Text(model.status).font(IslandFont.body).foregroundStyle(IslandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            if let app = defaultMusicApp {
                Button("Open \(app.name)") { NSWorkspace.shared.open(app.url) }
                    .buttonStyle(IslandPillStyle(prominent: false, compact: true))
            }
            if model.accessSource != nil {
                Button("Enable access", action: model.enableAccess)
                    .buttonStyle(IslandPillStyle(prominent: true, compact: true))
                    .disabled(model.isBusy)
            }
        }
    }

    /// The "Default music app" from Media settings, when it is installed.
    private var defaultMusicApp: (name: String, url: URL)? {
        let id = AppSettings.shared.defaultMusicApp
        guard !id.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(max(0, seconds), 604_800))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct MusicArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                // Takes the frame it is given and fills it, so the clip below cuts at that frame: a
                // 16:9 video cover (an upload's thumbnail) used to keep its width and spill over the title.
                Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }
            } else {
                ZStack {
                    // Soft blurred wash while a cover loads; the note is only a whisper.
                    LinearGradient(colors: [Color(white: 0.34), Color(white: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 60)
                    Image(systemName: "music.note").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The saved position of a quit player, drawn like PlaybackTimeline but not seekable.
private struct SavedPositionTimeline: View {
    let position: TimeInterval
    let duration: TimeInterval

    var body: some View {
        let clamped = min(duration, max(0, position))
        HStack(spacing: 13) {
            Text(time(clamped)).frame(width: 65, alignment: .leading)
            Capsule().fill(.white.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.86)).frame(width: 344 * clamped / duration)
                }
                .clipShape(Capsule())
                .frame(width: 344, height: 10)
            Text("−\(time(duration - clamped))").frame(width: 65, alignment: .trailing)
        }
        .foregroundStyle(IslandInk.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved position")
        .accessibilityValue("\(time(clamped)) of \(time(duration))")
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(max(0, seconds), 604_800))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Transport glyph with a soft hover halo, a springy press and symbol morphs.
private struct MusicTransportButton: View {
    let symbol: String
    let label: String
    var prominent = false
    var disabled = false
    let action: () -> Void
    @State private var hovered = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 44 : 34, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered ? 1 : 0.9))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, options: .speed(1.4), value: prominent ? 0 : taps)
                .frame(width: 80, height: 80)
                .background(hovered && !disabled ? IslandFill.subtle : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.86))
        .disabled(disabled)
        .help(label).accessibilityLabel(label)
        .onHover { hovered = $0 }
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    }
}

/// AirPlay-style route picker glyph; its halo stays lit while the drawer is open.
private struct OutputRouteButton: View {
    let symbol: String
    let open: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                .contentTransition(.identity)
                .transaction { $0.animation = nil }
                .frame(width: 64, height: 64)
                .background(open ? IslandFill.raised : hovered ? IslandFill.subtle : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.88))
        .onHover { hovered = $0 }
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: open)
    }
}

private struct OutputDeviceRow: View {
    let name: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium)).frame(width: 36)
                Text(name).font(.system(size: 21, weight: .medium)).lineLimit(1)
                Spacer()
                // Control Center style: a filled white disc with a check, or an empty gray one.
                ZStack {
                    Circle().fill(selected ? Color.white : Color.white.opacity(0.28))
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.black)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            }
            .foregroundStyle(IslandInk.primary)
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(selected ? IslandFill.selected : hovered ? IslandFill.raised : IslandFill.subtle,
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.98))
        .onHover { hovered = $0 }
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
        .animation(NotchMotion.press(reduceMotion: reduceMotion), value: selected)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The playing app's icon, tucked onto the artwork corner like the system player.
private struct SourceBadge: View {
    let source: NowPlayingSource

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .accessibilityHidden(true)
        }
    }
}

/// Favorite (Apple Music) or shuffle (Spotify) beside the transport controls.
private struct MusicSideButton: View {
    var kind: MediaButtonKind = .favorite
    let snapshot: NowPlayingSnapshot
    let disabled: Bool
    let favorite: () -> Void
    let shuffle: () -> Void
    @State private var hovered = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFavoriteControl: Bool { kind == .favorite }
    private var isOn: Bool { (isFavoriteControl ? snapshot.isFavorite : snapshot.isShuffling) ?? false }

    var body: some View {
        Button {
            taps += 1
            isFavoriteControl ? favorite() : shuffle()
        } label: {
            Image(systemName: isFavoriteControl ? (isOn ? "star.fill" : "star") : "shuffle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isOn ? (isFavoriteControl ? Color.pink : Color.white) : .white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .frame(width: 64, height: 64)
                .background(hovered ? IslandFill.subtle : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.86))
        .disabled(disabled)
        .onHover { hovered = $0 }
        .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
        .help(isFavoriteControl ? (isOn ? "Remove from Favorites" : "Favorite") : (isOn ? "Shuffle off" : "Shuffle"))
        .accessibilityLabel(isFavoriteControl ? "Favorite" : "Shuffle")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct MusicActivityWaveform: View {
    let isPlaying: Bool
    var tint: Color?

    var body: some View {
        PlaybackWaveform(isPlaying: isPlaying, colored: true, tint: tint)
            .frame(width: 23, height: 25)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}
