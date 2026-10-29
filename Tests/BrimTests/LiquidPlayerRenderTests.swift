import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the player card, Playing Next column and the three Liquid Player sizes to `.renders/`.
@MainActor
@Suite(.serialized)
struct LiquidPlayerRenderTests {
  private let us = "\u{1F}"

  private func playing() async throws -> NowPlayingModel {
    let value = NowPlayingSnapshot(source: .music, title: "Kill Bill", artist: "SZA", album: "SOS",
      duration: 153, position: 69, isPlaying: true, artworkData: try artwork(), isFavorite: false)
    let model = NowPlayingModel(provider: FixtureProvider(value: value), enabledSources: [.music], stream: nil)
    await model.refreshNow()
    for _ in 0..<100 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(20)) }
    return model
  }

  private func queueModel() async -> PlayingNextModel {
    let rows = ["Blue Hour|Nova Coast", "Low Tide|Harbor Lights", "Paper Planes|The Quiet Hours", "Dunes|Golden Field", "Still Life|Vase & Vine"]
    let output = rows.enumerated().map { i, row in
      let parts = row.split(separator: "|").map(String.init)
      return "\(i + 5)\(us)id\(i)\(us)\(parts[0])\(us)\(parts[1])\(us)180"
    }.joined(separator: "\n")
    let model = PlayingNextModel(read: { _ in output }, perform: { _ in "" }, fetchArtwork: { [self] id in (try? artwork(hue: Double((id * 23) % 100) / 100, side: 120)) })
    return model
  }

  private func settled(_ queue: PlayingNextModel, for track: NowPlayingTrack?) async {
    queue.refresh(for: track, force: true)
    try? await Task.sleep(for: .milliseconds(150))
  }

  @Test func notchCardWithPlayingNextRenders() async throws {
    let model = try await playing()
    let queue = await queueModel()
    await settled(queue, for: model.track)
    let size = MusicPlayerCard.preferredSize(showsQueue: true)
    let bitmap = try await render(MusicPlayerCard(model: model, queue: queue), name: "player-card-queue", size: size)
    #expect(bright(bitmap, CGRect(x: 340, y: 60, width: 280, height: 120)) > 100, "queue rows must draw")
  }

  @Test func notchCardWithLyricsRenders() async throws {
    let model = try await playing()
    let lrc = "[01:00.00]I might kill my ex\n[01:05.00]Not the best idea\n[01:10.00]His new girlfriend's next\n[01:15.00]How'd I get here?"
    let lyrics = LyricsModel(state: .ready(LRCParser.parse(lrc)))
    let size = MusicPlayerCard.preferredSize(showsQueue: true)
    let bitmap = try await render(
      MusicPlayerCard(model: model, queue: await queueModel(), lyrics: lyrics, showsLyrics: .constant(true)),
      name: "player-card-lyrics", size: size)
    #expect(bright(bitmap, CGRect(x: 340, y: 60, width: 280, height: 120)) > 100, "lyrics must draw")
  }

  @Test func notchCardWithAudioOutputsRenders() async throws {
    let model = try await playing()
    let outputs = AudioOutputModel(provider: CardOutputProvider())
    await outputs.refreshNow()
    let size = MusicPlayerCard.preferredSize(showsQueue: true)
    let bitmap = try await render(
      MusicPlayerCard(model: model, queue: await queueModel(), outputs: outputs, showsOutputs: .constant(true)),
      name: "player-card-outputs", size: size)
    #expect(bright(bitmap, CGRect(x: 340, y: 60, width: 280, height: 120)) > 100, "the output list must draw")
    #expect(MusicPlayerCard.showsSidePanel(queueOpen: false, queueAvailable: false, lyricsOpen: false, outputsOpen: true))
  }

  @Test func lyricsReplaceThePlayingNextColumn() {
    #expect(MusicPlayerCard.showsSidePanel(queueOpen: false, queueAvailable: false, lyricsOpen: true))
    #expect(MusicPlayerCard.showsSidePanel(queueOpen: true, queueAvailable: true, lyricsOpen: false))
    #expect(!MusicPlayerCard.showsSidePanel(queueOpen: true, queueAvailable: false, lyricsOpen: false))
  }

  @Test func notchCardWithoutQueueRenders() async throws {
    let model = try await playing()
    let size = MusicPlayerCard.preferredSize(showsQueue: false)
    let bitmap = try await render(MusicPlayerCard(model: model, queue: await queueModel(), showsQueue: .constant(false)),
                                  name: "player-card", size: size)
    #expect(bright(bitmap, CGRect(x: 20, y: 130, width: 300, height: 40)) > 50)
  }

  @Test func islandPillCardRenders() async throws {
    let model = try await playing()
    let size = MusicPlayerCard.preferredSize(showsQueue: false, topInset: 20)
    let bitmap = try await render(MusicPlayerCard(model: model, queue: await queueModel(), topInset: 20, showsQueue: .constant(false)),
                                  name: "player-card-pill", size: size)
    #expect(bright(bitmap, CGRect(x: 20, y: 90, width: 300, height: 40)) > 50)
  }

  @Test func floatingPlayerSizesRender() async throws {
    let model = try await playing()
    let queue = await queueModel()
    await settled(queue, for: model.track)
    for (name, kind, panel) in [("liquid-mini", LiquidPlayerSize.mini, LiquidPlayerPanel.cover),
                                ("liquid-player", .player, .cover), ("liquid-expanded", .expanded, .cover),
                                ("liquid-expanded-queue", .expanded, .queue)] {
      let size = LiquidPlayerPolicy.size(for: kind)
      let view = LiquidPlayerView(model: model, queue: queue, height: size.height, panel: panel)
      let bitmap = try await render(view, name: name, size: CGSize(width: size.width + 40, height: size.height + 40), padding: 20)
      #expect(bright(bitmap, CGRect(x: 20, y: 20, width: size.width, height: size.height)) > 30, "\(name) draws")
    }
  }

  @Test func skeletonWhileSkippingRenders() async throws {
    let model = try await playing()
    model.command(.next)
    #expect(model.track?.isTransitioning == true)
    let size = LiquidPlayerPolicy.size(for: .player)
    _ = try await render(LiquidPlayerView(model: model, height: size.height), name: "liquid-skeleton",
                         size: CGSize(width: size.width + 40, height: size.height + 40), padding: 20)
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

  private func bright(_ bitmap: NSBitmapImageRep, _ area: CGRect) -> Int {
    let scale = CGFloat(bitmap.pixelsWide) / max(1, bitmap.size.width)
    var count = 0
    for y in stride(from: Int(area.minY * scale), to: min(bitmap.pixelsHigh, Int(area.maxY * scale)), by: 2) {
      for x in stride(from: Int(area.minX * scale), to: min(bitmap.pixelsWide, Int(area.maxX * scale)), by: 2) {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent > 0.5 && c.greenComponent > 0.5 && c.blueComponent > 0.5 { count += 1 }
      }
    }
    return count
  }

  /// A colourful, busy cover (sea, sun, swimmer) so tint, crop and corner radius are judged on real-looking art.
  private func artwork(hue: Double = 0.58, side: Int = 600) throws -> Data {
    let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let f = CGFloat(side)
    func color(_ h: Double, _ s: CGFloat, _ b: CGFloat) -> CGColor {
      let c = NSColor(hue: CGFloat(h.truncatingRemainder(dividingBy: 1)), saturation: s, brightness: b, alpha: 1)
      return c.usingColorSpace(.deviceRGB)!.cgColor
    }
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [color(hue, 0.85, 0.75), color(hue + 0.08, 0.95, 0.22)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: f), end: CGPoint(x: f, y: 0), options: [])
    for row in 0..<14 {
      context.setStrokeColor(color(hue, 0.3, 0.95).copy(alpha: 0.18)!)
      context.setLineWidth(f * 0.012)
      let y = f * (0.05 + CGFloat(row) * 0.07)
      context.move(to: CGPoint(x: 0, y: y))
      for x in stride(from: CGFloat(0), through: f, by: f / 24) {
        context.addLine(to: CGPoint(x: x, y: y + sin(x / f * 18 + CGFloat(row)) * f * 0.018))
      }
      context.strokePath()
    }
    context.setFillColor(color(hue + 0.45, 0.8, 1).copy(alpha: 0.95)!)
    context.fillEllipse(in: CGRect(x: f * 0.62, y: f * 0.66, width: f * 0.2, height: f * 0.2))
    context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: f * 0.15, y: f * 0.38, width: f * 0.85, height: f * 0.02))
    context.setFillColor(CGColor(red: 0.1, green: 0.08, blue: 0.12, alpha: 1))
    context.fillEllipse(in: CGRect(x: f * 0.38, y: f * 0.42, width: f * 0.05, height: f * 0.05))
    return try ImageEncoder.pngDataPreservingAlpha(
      from: NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: side, height: side)))
  }

  private actor FixtureProvider: NowPlayingProviding {
    let value: NowPlayingSnapshot?
    init(value: NowPlayingSnapshot?) { self.value = value }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { value }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }
}

private struct CardOutputProvider: AudioOutputProviding {
  func snapshot() async throws -> AudioOutputSnapshot {
    AudioOutputSnapshot(devices: [
      AudioOutputDevice(id: 1, name: "Alex’s AirPods Pro", icon: "airpodspro"),
      AudioOutputDevice(id: 2, name: "DELL S3425DW", icon: "display"),
      AudioOutputDevice(id: 3, name: "MacBook Pro Speakers", icon: "laptopcomputer"),
    ], selectedID: 1)
  }
  func select(_ id: UInt32) async throws -> AudioOutputSnapshot { try await snapshot() }
}
