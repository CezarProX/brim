import SwiftUI

/// Refresh only the timeline between source samples, without relaying out the notch.
struct PlaybackTimeline: View {
    let track: NowPlayingTrack
    let isBusy: Bool
    let seek: (TimeInterval, NowPlayingSnapshot) -> Void
    @State private var preview: TimeInterval?
    @State private var dragTrack: NowPlayingSnapshot?
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The scrubber thickens under the pointer, like the system Now Playing bar.
    private var active: Bool { hovered || preview != nil }

    static func position(x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval? {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return nil }
        return min(1, max(0, x / width)) * duration
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !track.isPlaying)) { context in
            let position = preview ?? track.position(at: context.date)
            HStack(spacing: 13) {
                Text(time(position)).frame(width: 65, alignment: .leading)
                    .foregroundStyle(active ? IslandInk.secondary : IslandInk.tertiary)
                Capsule().fill(.white.opacity(active ? 0.2 : 0.14))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(active ? 1 : 0.86))
                            .frame(width: 344 * min(1, max(0, position / track.duration)))
                    }
                    .clipShape(Capsule())
                    .frame(width: 344, height: active ? 15 : 10)
                    .frame(height: 32).contentShape(Rectangle())
                    .onHover { hovered = $0 }
                    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: active)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isBusy else { return }
                            if dragTrack == nil { dragTrack = track.snapshot }
                            preview = Self.position(x: value.location.x, width: 344, duration: track.duration)
                        }
                        .onEnded { value in
                            defer { preview = nil; dragTrack = nil }
                            guard !isBusy, let expected = dragTrack,
                                  let target = Self.position(x: value.location.x, width: 344, duration: expected.duration) else { return }
                            seek(target, expected)
                        })
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(time(position)) of \(time(track.duration))")
                    .accessibilityAdjustableAction { direction in
                        guard !isBusy else { return }
                        let delta: TimeInterval = direction == .increment ? 5 : -5
                        seek(min(track.duration, max(0, position + delta)), track.snapshot)
                    }
                Text("−\(time(max(0, track.duration - position)))")
                    .frame(width: 65, alignment: .trailing)
                    .foregroundStyle(active ? IslandInk.secondary : IslandInk.tertiary)
            }
        }
        .onDisappear { preview = nil; dragTrack = nil }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(max(0, seconds), 604_800))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
