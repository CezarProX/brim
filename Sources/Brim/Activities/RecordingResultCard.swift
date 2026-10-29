import AVKit
import SwiftUI

/// The card shown after a native screen recording stops: a preview that plays in place, the file's
/// name, length and size, and what to do next: edit it in Studio, find it, share it, copy it.
/// Sized for the open island's ~560 x 200 content area.
struct RecordingResultCard: View {
    let result: RecordingResult
    var watch: () -> Void = {}
    var reveal: () -> Void = {}
    var copy: () -> Void = {}
    var trash: () -> Void = {}
    var studio: (() -> Void)?
    var share: ((NSView) -> Void)?
    var close: (() -> Void)?
    /// Starts out playing the preview (tests and renders leave it off).
    var playing = false

    @State private var isPlaying = false
    @State private var copied = false
    @State private var shareAnchor = ShareAnchor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            preview
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.url.lastPathComponent).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(Self.length(result.duration)) · \(result.sizeText) · \(Self.place(of: result.url))")
                        .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let studio {
                        Button(action: studio) { Label("Edit in Studio", systemImage: "slider.horizontal.below.rectangle") }
                            .buttonStyle(CaptureAppButtonStyle(prominent: true, tint: IslandTint.recording))
                            .help("Trim, restyle and export this recording")
                    } else {
                        Button(action: watch) { Label("Open", systemImage: "play.fill") }
                            .buttonStyle(CaptureAppButtonStyle(prominent: true, tint: IslandTint.recording))
                    }
                    Button(action: reveal) { Label("Show in Finder", systemImage: "magnifyingglass") }
                        .buttonStyle(CaptureAppButtonStyle())
                }
                HStack(spacing: 8) {
                    if share != nil {
                        iconButton("square.and.arrow.up", "Share") { if let share { share(shareAnchor.view) } }
                            .background(ShareAnchorView(anchor: shareAnchor))
                    }
                    iconButton(copied ? "checkmark" : "doc.on.doc", "Copy file") { copy(); flashCopied() }
                    iconButton("trash", "Move to Trash", trash)
                    Spacer(minLength: 0)
                }
            }
            .padding(.trailing, close == nil ? 0 : 22)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous).fill(IslandFill.subtle))
        .overlay(alignment: .topTrailing) {
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandInk.tertiary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss")
            }
        }
        .onAppear { isPlaying = playing }
    }

    private var preview: some View {
        ZStack {
            if isPlaying {
                InlinePlayer(url: result.url)
            } else {
                Button { withAnimation(NotchMotion.feedback(reduceMotion: reduceMotion)) { isPlaying = true } } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = result.thumbnail {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(IslandFill.raised)
                                .overlay { Image(systemName: "film").font(.title).foregroundStyle(IslandInk.tertiary) }
                        }
                        Text(Self.length(result.duration)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 2).background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white).padding(6)
                    }
                    .overlay {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressStyle(pressedScale: 0.97))
                .help("Play here")
                .accessibilityLabel("Play recording")
            }
        }
        .frame(width: 200, height: 125)
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous).strokeBorder(IslandFill.hairline) }
    }

    private func iconButton(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 30) }
            .buttonStyle(CaptureAppButtonStyle()).help(label).accessibilityLabel(label)
    }

    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    static func length(_ seconds: TimeInterval) -> String { LockTimeFormat.clock(seconds) }

    /// "Desktop": the folder the file sits in.
    static func place(of url: URL) -> String { url.deletingLastPathComponent().lastPathComponent }
}

/// Plays the recording in place with the system's inline controls.
private struct InlinePlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        let player = AVPlayer(url: url)
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause() }
}

/// Remembers the share button's NSView so the system share menu can open next to it.
@MainActor
final class ShareAnchor {
    var view = NSView()
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// Live-model wrapper the shell can drop in.
struct RecordingResultCardHost: View {
    @ObservedObject var model: RecordingResultModel
    var body: some View {
        if let result = model.result {
            RecordingResultCard(result: result, watch: model.watch, reveal: model.reveal, copy: model.copy,
                                trash: model.trash, studio: model.openInStudio, share: model.share, close: model.dismiss)
        }
    }
}
