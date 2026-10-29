import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the media view with lyrics and the compact visualizer to `.renders/` for a visual check.
@MainActor
@Suite(.serialized)
struct MediaRenderTests {
  private static let lrc = """
    [00:70.00]
    [01:08.00]I was walking down the avenue
    [01:12.50]Neon lights were calling out my name
    [01:17.00]<01:17.00>Every <01:17.60>single <01:18.20>step <01:18.80>felt <01:19.40>like <01:20.00>a <01:20.40>dream
    [01:24.00]And the city never sleeps tonight
    [01:29.00]We were chasing something just out of reach
    [01:34.00]Under a sky of electric blue
    """

  private func model(title: String, position: TimeInterval) async throws -> NowPlayingModel {
    let value = NowPlayingSnapshot(source: .music, title: title, artist: "The Fixture Band",
      album: "Album", duration: 215, position: position, isPlaying: false,
      artworkData: try artwork(), isFavorite: true)
    let model = NowPlayingModel(provider: Provider(value: value), enabledSources: [.music])
    await model.refreshNow()
    for _ in 0..<100 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(20)) }
    return model
  }

  @Test func playerWithLyricsDrawerRenders() async throws {
    let defaults = AppSettings.shared
    defaults.lyricsEnabled = true
    defer { defaults.lyricsEnabled = false; defaults.mediaRightButtons = [.output] }
    defaults.mediaRightButtons = [.lyrics, .output]
    let player = try await model(title: "Midnight Avenue (Extended Anniversary Remaster)", position: 78.4)
    let lyrics = LyricsModel(state: .ready(LRCParser.parse(Self.lrc)))
    let bitmap = try await render(
      NowPlayingView(model: player, lyrics: lyrics, showingLyrics: true), name: "media-lyrics", size: CGSize(width: 600, height: 470))
    #expect(brightPixels(bitmap, in: CGRect(x: 60, y: 300, width: 480, height: 150)) > 200, "active lyric line must be visible")
  }

  @Test func noLyricsStateRenders() async throws {
    let player = try await model(title: "Quiet Song", position: 20)
    let bitmap = try await render(
      NowPlayingView(model: player, lyrics: LyricsModel(state: .none), showingLyrics: true), name: "media-no-lyrics",
      size: CGSize(width: 600, height: 470))
    #expect(brightPixels(bitmap, in: CGRect(x: 200, y: 300, width: 200, height: 120), floor: 0.25) > 20)
  }

  @Test func compactVisualizerRenders() async throws {
    let strip = HStack(spacing: 18) {
      ForEach([[0.2, 0.6, 0.9, 0.5, 0.3, 0.15], [0.9, 0.7, 0.4, 0.8, 0.5, 0.3]], id: \.self) { levels in
        LiveBarsPreview(levels: levels.map(Float.init), gradient: false)
        LiveBarsPreview(levels: levels.map(Float.init), gradient: true)
      }
    }.padding(20)
    let bitmap = try await render(strip, name: "media-visualizer", size: CGSize(width: 260, height: 70))
    #expect(brightPixels(bitmap, in: CGRect(x: 0, y: 0, width: 260, height: 70)) > 20)
  }

  @Test func settingsSectionRenders() async throws {
    _ = try await render(
      Form { MediaSettingsSection() }.formStyle(.grouped).background(Color(white: 0.16)),
      name: "media-settings", size: CGSize(width: 560, height: 900))
  }

  // MARK: helpers

  private struct LiveBarsPreview: NSViewRepresentable {
    let levels: [Float]
    let gradient: Bool
    func makeNSView(context: Context) -> WaveformLayerView {
      let view = WaveformLayerView(frame: CGRect(x: 0, y: 0, width: 23, height: 18))
      let tint = NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1)
      let colors = gradient
        ? [tint.blended(withFraction: 0.4, of: .white) ?? tint, tint.blended(withFraction: 0.3, of: .black) ?? tint]
        : [NSColor.white.withAlphaComponent(0.78)]
      view.configure(.init(count: 6, colors: colors, playing: true, reduceMotion: true, live: true))
      view.frame = CGRect(x: 0, y: 0, width: 23, height: 18)
      view.apply(levels: levels)
      return view
    }
    func updateNSView(_ view: WaveformLayerView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WaveformLayerView, context: Context) -> CGSize? {
      CGSize(width: 23, height: 18)
    }
  }

  private func render<V: View>(_ content: V, name: String, size: CGSize) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
      .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
    return bitmap
  }

  private func brightPixels(_ bitmap: NSBitmapImageRep, in area: CGRect, floor: CGFloat = 0.5) -> Int {
    let scale = CGFloat(bitmap.pixelsWide) / (bitmap.size.width == 0 ? 1 : bitmap.size.width)
    var count = 0
    for y in stride(from: Int(area.minY * scale), to: min(bitmap.pixelsHigh, Int(area.maxY * scale)), by: 2) {
      for x in stride(from: Int(area.minX * scale), to: min(bitmap.pixelsWide, Int(area.maxX * scale)), by: 2) {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent > floor && c.greenComponent > floor && c.blueComponent > floor { count += 1 }
      }
    }
    return count
  }

  private func artwork() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [CGColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1), CGColor(red: 0.3, green: 0.2, blue: 0.7, alpha: 1)] as CFArray,
      locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 128, y: 128), options: [])
    return try ImageEncoder.pngDataPreservingAlpha(
      from: NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 128, height: 128)))
  }

  private actor Provider: NowPlayingProviding {
    let value: NowPlayingSnapshot?
    init(value: NowPlayingSnapshot?) { self.value = value }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { value }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }
}
