import SwiftUI

/// Three synced lyric lines above the lock-screen media card. The active line is bright with a soft
/// halo; its neighbours are dim and blurred. Reuses the island's `LyricsModel`, so no extra fetching.
struct LockScreenLyricsView: View {
    @ObservedObject var model: LyricsModel
    let track: NowPlayingTrack
    /// Test hook: pins the clock instead of following the track.
    var fixedTime: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let lyrics = model.state.lyrics {
                TimelineView(.animation(minimumInterval: 0.1, paused: fixedTime == nil && !track.isPlaying)) { context in
                    lines(LockLyricsLines.rows(lyrics: lyrics, time: fixedTime ?? track.position(at: context.date)))
                }
            } else {
                Color.clear
            }
        }
        .frame(width: LockLyricsLayout.width, height: LockLyricsLayout.height)
        .accessibilityElement(children: .contain)
    }

    private func lines(_ rows: [LockLyricsLines.Row]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                let active = row.role == .active
                Text(LockLyricsLines.displayText(row))
                    .font(.system(size: active ? 28 : 20, weight: active ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(active ? 1 : 0.42))
                    .shadow(color: .white.opacity(active ? 0.55 : 0), radius: active ? 14 : 0)
                    .blur(radius: active ? 0 : 1.6)
                    .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .offset(y: row.role == .next ? 12 : -12)))
                    .accessibilityHidden(!active)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.1), value: rows)
        .shadow(color: .black.opacity(0.35), radius: 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
