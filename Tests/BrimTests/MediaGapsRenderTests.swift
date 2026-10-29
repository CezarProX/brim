import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the new repeat / playlist buttons, lyrics badge, synthesized word sweep and floating
/// lyrics to `.renders/` for a visual check.
@MainActor
@Suite(.serialized)
struct MediaGapsRenderTests {
  private static let lrc = """
    [00:05.00]I was walking down the avenue tonight
    [00:11.00]Neon lights were calling out my name
    [00:17.00]And the city never sleeps tonight
    [00:23.00]We were chasing something out of reach
    """

  private func model() async throws -> NowPlayingModel {
    var value = NowPlayingSnapshot(source: .music, title: "Midnight Avenue", artist: "The Fixture Band",
      album: "Album", duration: 215, position: 13, isPlaying: false, artworkData: try artwork(), isFavorite: true)
    value.repeatMode = .all
    let model = NowPlayingModel(provider: Provider(value: value), enabledSources: [.music], stream: nil)
    await model.refreshNow()
    for _ in 0..<100 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(20)) }
    return model
  }

  @Test func notchPlayerShowsRepeatPlaylistAndBadge() async throws {
    let settings = AppSettings.shared
    settings.lyricsEnabled = true
    settings.mediaLeftButtons = [.repeat, .addToPlaylist]
    settings.mediaRightButtons = [.favorite, .output]
    defer { settings.lyricsEnabled = false; settings.mediaLeftButtons = [.favorite]; settings.mediaRightButtons = [.output] }
    let lyrics = LyricsModel(state: .ready(LRCParser.parse(Self.lrc)))
    let player = try await model()
    let bitmap = try await render(NowPlayingView(model: player, lyrics: lyrics), name: "gaps-notch-player",
                                  size: CGSize(width: 600, height: 250))
    #expect(bright(bitmap, CGRect(x: 30, y: 180, width: 170, height: 60), floor: 0.4) > 40, "left slots draw")
  }

  @Test func plainLRCGetsWordSweep() async throws {
    let player = try await model()
    let lyrics = LyricsModel(state: .ready(LRCParser.parse(Self.lrc)))
    let track = try #require(player.track)
    let bitmap = try await render(LyricsView(model: lyrics, track: track, fixedTime: 13.5), name: "gaps-word-sweep",
                                  size: CGSize(width: 600, height: 190))
    #expect(bright(bitmap, CGRect(x: 40, y: 60, width: 520, height: 70), floor: 0.9) > 40, "sung words are white")
  }

  @Test func liquidExpandedAndFloatingLyricsRender() async throws {
    let settings = AppSettings.shared
    settings.lyricsEnabled = true
    defer { settings.lyricsEnabled = false }
    let player = try await model()
    let lyrics = LyricsModel(state: .ready(LRCParser.parse(Self.lrc)))
    let size = LiquidPlayerPolicy.size(for: .expanded)
    for (name, panel) in [("gaps-liquid-cover", LiquidPlayerPanel.cover), ("gaps-liquid-floating", .floatingLyrics)] {
      let view = LiquidPlayerView(model: player, lyrics: lyrics, height: size.height, panel: panel)
      let bitmap = try await render(view, name: name, size: CGSize(width: size.width + 40, height: size.height + 40), padding: 20)
      #expect(bright(bitmap, CGRect(x: 20, y: 20, width: size.width, height: size.height), floor: 0.5) > 30)
    }
  }

  // MARK: helpers

  private func render<V: View>(_ content: V, name: String, size: CGSize, padding: CGFloat = 0) async throws -> NSBitmapImageRep {
    let backdrop = LinearGradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.95), Color(red: 0.55, green: 0.55, blue: 1.0)],
                                  startPoint: .top, endPoint: .bottom)
    let host = NSHostingView(rootView: content.padding(padding).frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(padding > 0 ? AnyView(backdrop) : AnyView(Color.black)).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(450))
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

  private func bright(_ bitmap: NSBitmapImageRep, _ area: CGRect, floor: CGFloat) -> Int {
    let scale = CGFloat(bitmap.pixelsWide) / max(1, bitmap.size.width)
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
    let context = try #require(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [CGColor(red: 0.1, green: 0.35, blue: 0.55, alpha: 1), CGColor(red: 0.02, green: 0.12, blue: 0.3, alpha: 1)] as CFArray,
      locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 256), end: CGPoint(x: 256, y: 0), options: [])
    context.setFillColor(CGColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 100, y: 110, width: 70, height: 6))
    return try ImageEncoder.pngDataPreservingAlpha(
      from: NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 256, height: 256)))
  }

  private actor Provider: NowPlayingProviding {
    let value: NowPlayingSnapshot?
    init(value: NowPlayingSnapshot?) { self.value = value }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { value }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }
}
