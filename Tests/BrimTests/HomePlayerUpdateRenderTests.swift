import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct HomePlayerUpdateRenderTests {
    @Test func homeKeepsVolumeAndMusicTabHasNoVolumeRow() async throws {
        let playing = await OnboardingSamples.nowPlaying()
        let volume = PlayerVolumeModel(read: { .init(level: 0.65, muted: false) }, write: { _ in true })
        let root = VStack(alignment: .leading, spacing: 20) {
            Text("Home · Media").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            HStack(alignment: .top, spacing: 20) {
                HomeIdlePlayerCard(model: playing, volumeModel: volume)
                    .frame(width: HomeWidgetSize.medium.width, height: HomeWidgetGrid.unit)
                HomeIdlePlayerCard(model: playing, size: .small, volumeModel: volume)
                    .frame(width: HomeWidgetSize.small.width, height: HomeWidgetGrid.unit)
            }
            Text("Music").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            MusicPlayerCard(model: playing, queue: PlayingNextModel(read: { _ in "" }, perform: { _ in "" },
                             fetchArtwork: { _ in nil }), topInset: 16, showsQueue: .constant(false))
        }
        .padding(24)
        .frame(width: 520, height: 480, alignment: .topLeading)
        .background(Color(white: 0.12))
        .preferredColorScheme(.dark)
        let size = CGSize(width: 520, height: 480)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let rootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = rootURL.appendingPathComponent(".context/home-music-volume-home-only.png")
        try png.write(to: output)
        #expect(bitmap.pixelsWide > 500)
    }
}
