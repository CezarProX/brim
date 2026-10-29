import SwiftUI

/// The "Playing Next" list beside the player: art 33, title, artist. Clicking a row (or its button)
/// plays it next and the header says so; double-clicking plays it now.
/// Rows reorder with a spring when one is moved to the top; the list fades out at its bottom edge.
struct PlayingNextColumn: View {
    @ObservedObject var queue: PlayingNextModel
    let track: NowPlayingTrack
    var topInset: CGFloat = 45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rowPitch: CGFloat = 49

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 20, alignment: .leading)
                .padding(.top, topInset - 6)
            content.padding(.top, 8)
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        if let next = queue.pendingNext {
            Text("Playing next: \(next.title)").foregroundStyle(Color.accentColor).lineLimit(1)
                .transition(.opacity)
        } else {
            Text("Playing Next").foregroundStyle(IslandInk.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if queue.items.isEmpty {
            if queue.needsChromeJavaScript {
                chromeJavaScriptHint.padding(.top, 14)
            } else {
                // Other failed reads show the plain empty state: script errors are logged, never displayed.
                Text(queue.isLoading ? "Loading…" : "Nothing queued after this song")
                    .font(.system(size: 13)).foregroundStyle(IslandInk.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            }
        } else if queue.needsChromeJavaScript {
            // The list came from the screen, but choosing from it needs page scripting.
            VStack(alignment: .leading, spacing: 6) {
                chromeJavaScriptHint
                list
            }
        } else {
            list
        }
    }

    private var chromeJavaScriptHint: some View {
        Text("To use the YouTube Music queue, turn on Allow JavaScript from Apple Events in Chrome: View › Developer.")
            .font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 14)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(queue.items.enumerated()), id: \.element.id) { offset, item in
                    QueueRow(item: item, image: queue.artwork[item.persistentID], showsAction: offset > 0,
                             isNext: queue.pendingNext?.id == item.id,
                             playNext: { queue.playNext(item, track: track) },
                             playNow: { queue.playNow(item, track: track) })
                    .frame(height: Self.rowPitch)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(reduceMotion ? nil : NotchMotion.spring(duration: 0.4, bounce: 0.12), value: queue.items.map(\.id))
        }
        .scrollIndicators(.hidden)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let image: NSImage?
    let showsAction: Bool
    let isNext: Bool
    let playNext: () -> Void
    let playNow: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            MusicArtworkView(image: image, cornerRadius: 7).frame(width: 33, height: 33)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
                Text(isNext ? "Plays next" : item.artist).font(.system(size: 12.5))
                    .foregroundStyle(isNext ? Color.accentColor : IslandInk.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsAction {
                Button(action: playNext) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(hovered ? 1 : 0.62))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(IslandPressStyle(pressedScale: 0.86))
                .help("Play next")
                .accessibilityLabel("Play \(item.title) next")
            }
        }
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: playNow)
        .onTapGesture(perform: playNext)
        .help("Click to play next, double-click to play now")
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
