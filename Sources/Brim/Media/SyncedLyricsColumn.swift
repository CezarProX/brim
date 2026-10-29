import SwiftUI

/// Synced lyrics beside the player, in the slot Playing Next uses.
/// Reuses the drawer's `LyricsView`, drawn in its 600-point reference space and scaled to fit.
struct SyncedLyricsColumn: View {
    @ObservedObject var lyrics: LyricsModel
    let track: NowPlayingTrack
    var topInset: CGFloat = 45
    /// The whole card's height; the column runs from just under the notch to the bottom edge.
    let height: CGFloat

    static let referenceWidth: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.referenceWidth
            LyricsView(model: lyrics, track: track, height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .padding(.top, max(0, topInset - 12))
        .padding(.bottom, 8)
        .frame(height: height)
        .clipped()
        .accessibilityLabel("Lyrics")
    }
}
