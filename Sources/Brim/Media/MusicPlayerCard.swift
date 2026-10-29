import SwiftUI

/// The in-notch music player: cover 66 with title / artist and a
/// live waveform, scrubber with elapsed and remaining time, prev / play-pause / next centred with
/// the output picker at the right, and (optionally) a "Playing Next" column behind a hairline.
/// Self-contained: size it with `preferredSize` and drop it anywhere.
struct MusicPlayerCard: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var queue: PlayingNextModel = .shared
    @ObservedObject var outputs: AudioOutputModel = .shared
    @ObservedObject var qualityModel: AudioQualityModel = .shared
    @ObservedObject var lyrics: LyricsModel = .shared
    /// Clearance above the content: the hardware notch on notched Macs, a small margin otherwise.
    var topInset: CGFloat = 45
    /// Whether the Playing Next column is open; nil keeps it in local state (open by default).
    var showsQueue: Binding<Bool>?
    @State private var localShowsQueue = true
    /// Whether the synced-lyrics column replaces Playing Next; nil keeps it in local state.
    var showsLyrics: Binding<Bool>?
    @State private var localShowsLyrics = false
    /// Whether the audio-output list replaces the column (the island grows to show it).
    var showsOutputs: Binding<Bool>?
    @State private var localShowsOutputs = false
    @State private var cardHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Layout measurements, in points.
    static let sideInset: CGFloat = 17
    static let columnWidth: CGFloat = 306
    static let queueWidth: CGFloat = 302
    static let artSize: CGFloat = 66

    static func preferredSize(showsQueue: Bool, topInset: CGFloat = 45) -> CGSize {
        let single = columnWidth + sideInset * 2
        return CGSize(width: single + (showsQueue ? queueWidth : 0), height: topInset + 159)
    }

    private var outputsOpen: Bool { showsOutputs?.wrappedValue ?? localShowsOutputs }
    private var lyricsOpen: Bool { (showsLyrics?.wrappedValue ?? localShowsLyrics) && !outputsOpen }
    private var queueOpen: Bool {
        (showsQueue?.wrappedValue ?? localShowsQueue) && queueAvailable && !lyricsOpen && !outputsOpen
    }
    private var queueAvailable: Bool { QueueCapability.supportsQueue(model.track?.snapshot.source) }
    private var sidePanelOpen: Bool { queueOpen || lyricsOpen || outputsOpen }

    /// The column beside the player: audio outputs, synced lyrics or Playing Next, one at a time.
    static func showsSidePanel(queueOpen: Bool, queueAvailable: Bool, lyricsOpen: Bool,
                               outputsOpen: Bool = false) -> Bool {
        outputsOpen || lyricsOpen || (queueOpen && queueAvailable)
    }

    var body: some View {
        let size = Self.preferredSize(showsQueue: sidePanelOpen, topInset: topInset)
        Group {
            if let track = model.track {
                HStack(spacing: 0) {
                    leftColumn(track)
                    if sidePanelOpen {
                        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 68)
                            .padding(.top, topInset - 3)
                            .frame(maxHeight: .infinity, alignment: .top)
                        Group {
                            if outputsOpen {
                                PlayerOutputColumn(outputs: outputs, topInset: topInset)
                            } else if lyricsOpen {
                                SyncedLyricsColumn(lyrics: lyrics, track: track, topInset: topInset,
                                                   height: size.height)
                            } else {
                                PlayingNextColumn(queue: queue, track: track, topInset: topInset)
                            }
                        }
                        .frame(width: Self.queueWidth)
                        .transition(.opacity)
                    }
                }
            } else {
                Text("Not Playing").font(IslandFont.title).foregroundStyle(IslandInk.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : NotchMotion.layout(reduceMotion: false), value: queueOpen)
        .animation(reduceMotion ? nil : NotchMotion.layout(reduceMotion: false), value: lyricsOpen)
        .animation(reduceMotion ? nil : NotchMotion.layout(reduceMotion: false), value: outputsOpen)
        .onHover { cardHovered = $0 }
        .onAppear { queue.refresh(for: model.track) }
        .onChange(of: model.track?.songKey) { _, _ in queue.refresh(for: model.track) }
        .preferredColorScheme(.dark)
    }

    private func leftColumn(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: 0) {
            header(track)
            PlayerScrubber(track: track, seek: model.seek)
                .padding(.top, 6)
            controls(track).padding(.top, 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.top, topInset)
        .frame(width: Self.columnWidth + Self.sideInset * 2)
    }

    private func header(_ track: NowPlayingTrack) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: model.openTrack) {
                PlayerArtwork(track: track, cornerRadius: 12.5, drift: false)
                    .frame(width: Self.artSize, height: Self.artSize)
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.97))
            .accessibilityLabel("Open current song")
            .disabled(track.isTransitioning)
            PlayerTitleBlock(track: track, onOpenTrack: model.openTrack, onOpenArtist: model.openArtist)
                .frame(height: Self.artSize, alignment: .center)
            VStack(alignment: .trailing, spacing: 6) {
                AutomixWaveformSlot(track: track, tint: ArtworkTint.color(for: track.artwork))
                    .frame(width: 23, height: 16)
                if let quality = qualityModel.quality { AudioQualityBadge(quality: quality) }
            }
            .padding(.top, 16)
            .popOutHandle()
        }
        .frame(height: Self.artSize)
    }

    private func controls(_ track: NowPlayingTrack) -> some View {
        ZStack {
            PlayerTransport(track: track, model: model)
            HStack {
                // The card carries only transport + output. The Playing Next toggle sits at
                // the left while the column is closed, and fades in on hover once it is open.
                HStack(spacing: 0) {
                    if queueAvailable {
                        PlayerGlyphButton(symbol: "list.bullet", label: queueOpen ? "Hide Playing Next" : "Show Playing Next",
                                          size: 17, frame: 36, quiet: true, action: toggleQueue)
                    }
                    PlayerGlyphButton(symbol: "quote.bubble", label: lyricsOpen ? "Hide Lyrics" : "Show Lyrics",
                                      size: 17, frame: 36, quiet: true, action: toggleLyrics)
                }
                .opacity(sidePanelOpen && !cardHovered ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: cardHovered)
                Spacer()
                outputButton
            }
        }
        .frame(height: 44)
        .contextMenu { extras(track) }
    }

    private func toggleQueue() {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
            setOutputsOpen(false)
            if lyricsOpen {
                setLyricsOpen(false)
                setQueueOpen(true)
            } else {
                setQueueOpen(!(showsQueue?.wrappedValue ?? localShowsQueue))
            }
        }
    }

    /// Lyrics are opt-in because the song is looked up on lrclib.net; pressing the button is that opt-in.
    private func toggleLyrics() {
        if !lyricsOpen, !AppSettings.shared.lyricsEnabled {
            AppSettings.shared.lyricsEnabled = true
            MediaServices.shared.sync(model)
        }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
            let open = !lyricsOpen
            setOutputsOpen(false)
            setLyricsOpen(open)
        }
    }

    /// The island grows a list of outputs beside the player, like Control Center, instead of a menu.
    private func toggleOutputs() {
        if !outputsOpen { outputs.refresh() }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { setOutputsOpen(!outputsOpen) }
    }

    private func setOutputsOpen(_ open: Bool) {
        if let showsOutputs { showsOutputs.wrappedValue = open } else { localShowsOutputs = open }
    }

    private func setQueueOpen(_ open: Bool) {
        if let showsQueue { showsQueue.wrappedValue = open } else { localShowsQueue = open }
    }

    private func setLyricsOpen(_ open: Bool) {
        if let showsLyrics { showsLyrics.wrappedValue = open } else { localShowsLyrics = open }
    }

    /// Favorite / shuffle / repeat / playlist stay one right-click away instead of crowding the card.
    @ViewBuilder
    private func extras(_ track: NowPlayingTrack) -> some View {
        if let favorite = track.snapshot.isFavorite {
            Button(favorite ? "Remove from Favorites" : "Favorite", action: model.toggleFavorite)
        }
        if let shuffle = track.snapshot.isShuffling {
            Button(shuffle ? "Turn Shuffle Off" : "Turn Shuffle On", action: model.toggleShuffle)
        }
        if let mode = track.snapshot.repeatMode { Button(mode.title, action: model.cycleRepeat) }
    }

    private var outputButton: some View {
        PlayerGlyphButton(symbol: outputs.selectedDevice?.playerSymbol ?? "laptopcomputer",
                          label: outputsOpen ? "Hide audio outputs" : "Choose audio output",
                          size: 21, frame: 36, active: outputsOpen ? true : nil, action: toggleOutputs)
            .onAppear { outputs.refresh() }
            .help(outputs.selectedDevice.map { "Audio output: \($0.name)" } ?? "Choose audio output")
    }
}

/// The playing app's icon on the artwork corner.
struct SourceBadgeIcon: View {
    let source: NowPlayingSource

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .accessibilityHidden(true)
        }
    }
}
