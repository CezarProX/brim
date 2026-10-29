import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Wave-5 lock screen and HUD pieces to `.renders/` so the design can be looked at.
@MainActor
@Suite(.serialized)
struct LockHUDv2RenderTests {
  private func artwork() -> NSImage {
    NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
      NSGradient(colors: [NSColor(red: 0.98, green: 0.35, blue: 0.45, alpha: 1), NSColor(red: 0.25, green: 0.15, blue: 0.8, alpha: 1)])?
        .draw(in: rect, angle: 55)
      NSColor.white.withAlphaComponent(0.25).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 150, dy: 150)).fill()
      return true
    }
  }

  private var track: NowPlayingTrack {
    NowPlayingTrack(
      snapshot: NowPlayingSnapshot(source: .music, title: "Midnight City", artist: "M83", album: "Hurry Up",
                                   duration: 243, position: 96, isPlaying: true),
      artwork: artwork())
  }

  private var wallpaper: some View {
    LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.5), Color(red: 0.1, green: 0.2, blue: 0.9)], startPoint: .top, endPoint: .bottom)
  }

  private func outputDir() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Hosted render (materials need a real window).
  private func shoot<V: View>(_ view: V, size: CGSize, name: String) async throws {
    let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(700))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: try outputDir().appendingPathComponent("\(name).png"))
    #expect(png.count > 5_000)
  }

  @Test func artworkScene() async throws {
    let scene = LockScreenArtworkScene(info: LockMediaInfo(track: track), actions: LockCardActions(),
                                       now: Date(timeIntervalSince1970: 1_760_000_000))
    try await shoot(scene, size: CGSize(width: 1280, height: 800), name: "lock-artwork-scene")
  }

  @Test func lyricsOverCard() async throws {
    let lyrics = LRCParser.parse("[00:01.00]Stay with me in the blue hour\n[00:05.00]Hold the sky a little longer\n[00:09.00]Lights come on along the water\n[00:12.00]Every window holds a little gold")
    let model = LyricsModel(state: .ready(lyrics))
    let content = LockCardsContent(media: LockMediaInfo(track: track))
    let view = ZStack(alignment: .bottom) {
      wallpaper
      VStack(spacing: 14) {
        LockScreenLyricsView(model: model, track: track, fixedTime: 6.5)
        LockCardsStack(content: content, kinds: [.nowPlaying], look: .liquid, actions: LockCardActions())
      }
      .padding(.bottom, 60)
    }
    try await shoot(view, size: CGSize(width: 800, height: 520), name: "lock-lyrics")
  }

  @Test func edgeSliders() async throws {
    let view = ZStack(alignment: .leading) {
      wallpaper
      HStack(alignment: .center, spacing: 40) {
        EdgeSliderView(kind: .volume, level: 0.62, style: .wide)
        EdgeSliderView(kind: .volume, level: 0.62, style: .thin)
        EdgeSliderView(kind: .brightness, level: 0.35, style: .wide, tint: Color(red: 1, green: 0.84, blue: 0.3))
        EdgeSliderView(kind: .brightness, level: 0.9, style: .thin, tint: Color(red: 1, green: 0.84, blue: 0.3))
      }
      .padding(.leading, 30)
    }
    try await shoot(view, size: CGSize(width: 360, height: 300), name: "lock-edge-sliders")
  }

  private func stripShell<V: View>(_ content: V) -> some View {
    content
      .frame(width: 190 + 2 * HUDMetrics.wing, height: 32)
      .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(.black))
      .padding(14).background(LinearGradient(colors: [.indigo.opacity(0.7), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
      .environment(\.colorScheme, .dark)
  }

  private func write<V: View>(_ view: V, name: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: try outputDir().appendingPathComponent("\(name).png"))
  }

  @Test func downloadRingCompact() throws {
    func compact(_ snapshot: DownloadSnapshot) -> some View {
      stripShell(HStack(spacing: 0) {
        DownloadCompactLeading(snapshot: snapshot).frame(width: HUDMetrics.wing)
        Spacer(minLength: 190)
        DownloadCompactTrailing(snapshot: snapshot).frame(width: HUDMetrics.wing)
      })
    }
    let timed = DownloadSnapshot(name: "Xcode.xip", bytes: 700, fraction: 0.7, secondsLeft: 5, count: 1)
    let unknown = DownloadSnapshot(name: "a.zip", bytes: 48_000_000, fraction: nil, secondsLeft: nil, count: 1)
    try write(VStack(spacing: 10) { compact(timed); compact(unknown) }, name: "download-ring-compact")
  }

  @Test func airPodsCard() throws {
    let metrics = HUDMetrics(notchWidth: 190, closedHeight: 32)
    let pods = AirPodsBatteries(name: "Alex’s AirPods Pro", symbol: "airpodspro", left: 82, right: 76, caseLevel: 18)
    let flash = IslandFlash(title: pods.name, symbol: pods.symbol, tint: .white, value: nil, until: .distantFuture,
                            kind: .bluetooth, detail: "Connected", airPods: pods, shortTitle: "Connected")
    let size = metrics.cardSize(for: flash)
    let card = HUDMorphView(flash: flash, metrics: metrics, expanded: true)
      .background(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).fill(.black).frame(width: size.width, height: size.height))
      .frame(width: size.width + 20, height: size.height + 14, alignment: .top)
      .background(LinearGradient(colors: [.indigo.opacity(0.7), .teal.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
      .environment(\.colorScheme, .dark)
      .environment(\.airPodsVisualStillTime, AirPods3DMotion.introDuration)
    try write(card, name: "hud-airpods-card")
    let mode = IslandFlash(title: "Transparency", symbol: AirPodsListeningMode.transparency.symbol, tint: .orange, value: nil,
                           until: .distantFuture, kind: .bluetooth, detail: "AirPods Pro", shortTitle: "Transp.")
    try write(stripShell(HUDStripView(flash: mode, metrics: metrics)), name: "hud-airpods-mode-strip")
  }

  @Test func recordingCard() async throws {
    var result = RecordingResult(url: URL(fileURLWithPath: "/Users/me/Desktop/Screen Recording 2026-10-23 at 9.41.mov"),
                                 duration: 83, bytes: 48_300_000)
    result.thumbnail = artwork()
    let view = RecordingResultCard(result: result, close: {})
      .frame(width: 560, height: 200).padding(20).background(.black)
      .environment(\.colorScheme, .dark)
    try await shoot(view, size: CGSize(width: 600, height: 240), name: "recording-result-card")
  }

  @Test func symbolsExist() {
    for mode in AirPodsListeningMode.allCases {
      #expect(NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil) != nil, "\(mode.symbol)")
    }
    for name in ["airpods", "airpodspro", "airpodsmax", "airpods.gen3"] {
      #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
    }
  }
}
