import AppKit
import SwiftUI
import Testing
import Vision

@testable import Brim

@MainActor
@Suite(.serialized)
struct NotchHomeViewTests {
  /// The Music page is the player card: cover 66 pt at the left, transport beneath, and the Playing Next
  /// column to the right behind a hairline (Apple Music has a queue).
  /// The open shell around the player card: the notch shape's shoulders sit outside the card.
  private func card(floating: Bool) -> CGSize {
    let card = MusicPlayerCard.preferredSize(showsQueue: true, topInset: floating ? 20 : 45)
    return CGSize(width: card.width + (floating ? 0 : 2 * IslandPageLayout.openShoulder), height: card.height)
  }

  private func artworkArea(floating: Bool, dx: CGFloat = 0) -> CGRect {
    CGRect(x: (floating ? 0 : IslandPageLayout.openShoulder) + MusicPlayerCard.sideInset + 8 + dx, y: (floating ? 20 : 45) + 8, width: 50, height: 50)
  }

  @Test("Fixed hosting canvas keeps music centered and transparent outside the visible shell")
  func fixedCanvasKeepsShellAnchored() async throws {
    let rendered = try await render(
      expanded: true, floating: false, libraryRoundTrip: true,
      fixedCanvas: true)
    #expect(rendered.size == CGSize(width: 740, height: 502))
    let scale = CGFloat(rendered.bitmap.pixelsWide) / rendered.size.width
    let outside = try #require(rendered.bitmap.colorAt(x: Int(20 * scale), y: Int(100 * scale)))
    #expect(outside.alphaComponent < 0.01)
    let below = try #require(rendered.bitmap.colorAt(x: Int(300 * scale), y: Int(300 * scale)))
    #expect(below.alphaComponent < 0.01)
    let size = card(floating: false)
    let artwork = artworkArea(floating: false, dx: (rendered.size.width - size.width) / 2)
    #expect(greenPixels(rendered.bitmap, in: artwork, size: rendered.size) > 150)
    // The navigation capsule floats in the canvas a small gap below the shell.
    let capsuleTop = size.height + IslandNavigationLayout.gap
    let capsule = CGRect(x: (rendered.size.width - 100) / 2, y: capsuleTop, width: 100, height: 38)
    #expect(
      opaquePixels(rendered.bitmap, in: capsule, size: rendered.size) > 150,
      "The detached navigation capsule must render beneath the island")
  }

  @Test(
    "The Music page shows the actual current track", arguments: [false, true])
  func nowPlayingAppearsOnHome(floating: Bool) async throws {
    let rendered = try await render(expanded: true, floating: floating)
    #expect(rendered.size == card(floating: floating))
    #expect(
      greenPixels(rendered.bitmap, in: artworkArea(floating: floating), size: rendered.size) > 150,
      "The Music page must show album artwork immediately")
    let top: CGFloat = floating ? 20 : 45
    let controlsArea = CGRect(x: 90, y: top + 92, width: 160, height: 44)
    #expect(
      whitePixels(rendered.bitmap, in: controlsArea, size: rendered.size) > 60,
      "The transport controls must remain inside the expanded surface")
    let text = try recognizedText(in: rendered.bitmap)
    #expect(text.contains("playing next"), "Apple Music shows its queue beside the player")
  }

  @Test("Playback errors do not add an orange banner or expand the music panel")
  func playbackErrorKeepsPlayerCompact() async throws {
    let rendered = try await render(expanded: true, floating: false, playbackFailure: true)
    #expect(rendered.size == card(floating: false))
    let text = try recognizedText(in: rendered.bitmap)
    #expect(!text.contains("playback error"))
  }

  @Test("Tray round trip updates music geometry without waiting for the hover timer")
  func libraryNavigationKeepsTopAnchor() async throws {
    let rendered = try await render(expanded: true, floating: true, libraryRoundTrip: true)
    #expect(rendered.size == card(floating: true))
  }

  @Test("The output picker and queue sit in the player card, not in a drawer under it")
  func outputPickerLivesInTheCard() async throws {
    let rendered = try await render(expanded: true, floating: false)
    let lines = try recognizedText(in: rendered.bitmap)
    #expect(lines.contains("blue hour"))
    #expect(!lines.contains("fixture speakers"))
    #expect(rendered.size.height == card(floating: false).height)
  }

  @Test("Compact playback fits its hardware or floating surface", arguments: [false, true])
  func compactPlaybackFitsAroundHardware(floating: Bool) async throws {
    // The title beside the artwork has its own render test; this one checks the bare artwork fit.
    let settings = AppSettings.shared
    let saved = (settings.notchTrackTitle, settings.keepSongNameVisible)
    settings.notchTrackTitle = false
    settings.keepSongNameVisible = false
    defer { (settings.notchTrackTitle, settings.keepSongNameVisible) = saved }
    let rendered = try await render(expanded: false, floating: floating)
    let leftWing =
      floating
      ? CGRect(x: 114, y: 6, width: 23, height: 24)
      : CGRect(x: 84, y: 3, width: 28, height: 27)
    #expect(
      greenPixels(rendered.bitmap, in: leftWing, size: rendered.size) > 100,
      "Compact artwork must appear to the left of the hardware")
    var opaqueBelowNotch = 0
    let scale = CGFloat(rendered.bitmap.pixelsWide) / rendered.size.width
    let contentHeight: CGFloat = floating ? 36 : 32
    for y in stride(from: Int((contentHeight + 2) * scale), to: rendered.bitmap.pixelsHigh, by: 3) {
      for x in stride(from: 0, to: rendered.bitmap.pixelsWide, by: 3) {
        if let color = rendered.bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
          opaqueBelowNotch += 1
        }
      }
    }
    #expect(opaqueBelowNotch == 0, "Compact activity must stay within the collapsed height")
  }

  private func opaquePixels(_ bitmap: NSBitmapImageRep, in area: CGRect, size: CGSize) -> Int {
    pixels(bitmap, in: area, size: size) { $0.alphaComponent > 0.3 }
  }

  private func recognizedText(in bitmap: NSBitmapImageRep) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ro-RO", "en-US"]
    try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: " ").lowercased()
  }

  private func referenceArea(_ rect: CGRect, topInset: CGFloat = 0) -> CGRect {
    rect.applying(CGAffineTransform(scaleX: 0.7, y: 0.7)).offsetBy(dx: 0, dy: topInset)
  }

  private func render(
    expanded: Bool, floating: Bool, drawer: Bool = false, playbackFailure: Bool = false,
    libraryRoundTrip: Bool = false, fixedCanvas: Bool = false
  ) async throws -> (bitmap: NSBitmapImageRep, size: CGSize) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Brim-HomeTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = HomeRenderProvider(artworkData: try artwork(), playbackFailure: playbackFailure)
    let music = NowPlayingModel(provider: provider, enabledSources: [.music])
    await music.refreshNow()
    if playbackFailure {
      await music.command(.playPause)?.value
      #expect(music.status == "Fixture playback error")
    }
    let outputs = AudioOutputModel(provider: HomeOutputRenderProvider())
    await outputs.refreshNow()
    let presentation = NotchPresentation()
    presentation.geometry = NotchGeometry(
      screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      notchWidth: floating ? 0 : 184, notchHeight: floating ? 0 : 32,
      hasLiveActivity: true, audioDrawerExpanded: drawer, compactMusicLayout: true)
    presentation.geometry.musicSummaryHeight = 0
    presentation.updateActivities(IslandActivities(recording: false, call: false, music: true))
    presentation.isExpanded = expanded
    // The full player lives on the Music tab; Home is the widget shelf.
    if expanded { presentation.navigate(to: .showing(.music)) }
    presentation.isPresentingAudioOutputs = drawer
    let contentSize = expanded ? card(floating: floating) : presentation.geometry.expandedSize
    let size = fixedCanvas ? presentation.geometry.hostingFrame.size : contentSize
    let host = NSHostingView(
      rootView: NotchShelfView(
        presentation: presentation, store: ShelfStore(directory: directory),
        nowPlaying: music, calls: CallActivityModel(accessibilityTrusted: { false }),
        outputs: outputs,
        homeWidgets: HomeWidgetStore(widgets: [.media], persist: { _ in }),
        playingNext: Self.queue()))
    if fixedCanvas { host.sizingOptions = [] }
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(180))
    host.layoutSubtreeIfNeeded()
    // The card cross-fades its artwork in; let it settle before sampling pixels.
    if expanded {
      try await Task.sleep(for: .milliseconds(500))
      host.layoutSubtreeIfNeeded()
    }
    if libraryRoundTrip {
      let anchor = presentation.geometry.panelFrame.maxY
      let windowFrame = window.frame
      // The File Tray page is a 500-point grid.
      withAnimation(.easeInOut(duration: 0.28)) { presentation.navigate(to: .showing(.tray)) }
      try await Task.sleep(for: .milliseconds(350))
      host.layoutSubtreeIfNeeded()
      #expect(presentation.geometry.expandedSize.width == IslandPageLayout.trayWidth)
      #expect(presentation.geometry.panelFrame.maxY == anchor)
      if fixedCanvas { #expect(window.frame == windowFrame) }
      withAnimation(.easeInOut(duration: 0.28)) { presentation.navigate(to: .showing(.music)) }
      try await Task.sleep(for: .milliseconds(350))
      host.layoutSubtreeIfNeeded()
      #expect(presentation.geometry.expandedSize == contentSize)
      #expect(presentation.geometry.panelFrame.maxY == anchor)
      if fixedCanvas { #expect(window.frame == windowFrame) }
    }
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    if let destination = ProcessInfo.processInfo.environment["BRIM_SNAPSHOT_DIR"],
      !destination.isEmpty
    {
      let target = URL(fileURLWithPath: destination, isDirectory: true)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      let image = NSImage(size: size)
      image.addRepresentation(bitmap)
      let name =
        fixedCanvas
        ? "home-fixed-canvas"
        : (drawer
          ? "home-output-drawer"
          : (expanded
            ? (floating ? "home-floating" : "home-music")
            : (floating ? "compact-floating" : "compact-music")))
      try ImageEncoder.pngDataPreservingAlpha(from: image).write(
        to: target.appendingPathComponent("\(name).png"))
    }
    return (bitmap, size)
  }

  private func greenPixels(_ bitmap: NSBitmapImageRep, in area: CGRect, size: CGSize) -> Int {
    pixels(bitmap, in: area, size: size) { color in
      color.greenComponent > 0.65 && color.greenComponent - color.redComponent > 0.25
        && color.greenComponent - color.blueComponent > 0.3
    }
  }

  private func whitePixels(_ bitmap: NSBitmapImageRep, in area: CGRect, size: CGSize) -> Int {
    pixels(bitmap, in: area, size: size) { color in
      color.redComponent > 0.65 && color.greenComponent > 0.65 && color.blueComponent > 0.65
    }
  }

  private func pixels(
    _ bitmap: NSBitmapImageRep, in area: CGRect, size: CGSize, matching: (NSColor) -> Bool
  ) -> Int {
    var count = 0
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    for y in stride(from: Int(area.minY), to: Int(area.maxY), by: 2) {
      for x in stride(from: Int(area.minX), to: Int(area.maxX), by: 2) {
        if let color = bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?
          .usingColorSpace(.deviceRGB),
          matching(color)
        {
          count += 1
        }
      }
    }
    return count
  }

  private static func queue() -> PlayingNextModel {
    let us = "\u{1F}"
    let output = ["5\(us)a\(us)Blue Hour\(us)Nova Coast\(us)180", "6\(us)b\(us)Low Tide\(us)Harbor Lights\(us)200"]
      .joined(separator: "\n")
    return PlayingNextModel(read: { _ in output }, perform: { _ in "" }, fetchArtwork: { _ in nil })
  }

  private func artwork() throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: 128, height: 128, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.9, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    return try ImageEncoder.pngDataPreservingAlpha(
      from: NSImage(
        cgImage: try #require(context.makeImage()), size: CGSize(width: 128, height: 128)))
  }
}

private struct HomeOutputRenderProvider: AudioOutputProviding {
  func snapshot() async throws -> AudioOutputSnapshot {
    AudioOutputSnapshot(
      devices: [
        AudioOutputDevice(id: 1, name: "Fixture speakers", icon: "speaker.wave.2.fill"),
        AudioOutputDevice(id: 2, name: "Fixture headphones", icon: "headphones"),
      ], selectedID: 1)
  }
  func select(_ id: UInt32) async throws -> AudioOutputSnapshot { try await snapshot() }
}

private struct HomeRenderProvider: NowPlayingProviding {
  let artworkData: Data
  var playbackFailure = false
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
    NowPlayingSnapshot(
      source: source, title: "A song on your Mac", artist: "Fixture artist", album: "Fixture album",
      duration: 240, position: 80, isPlaying: true, artworkData: artworkData)
  }
  func perform(
    _ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken
  ) async throws {
    if playbackFailure {
      throw NSError(
        domain: "HomeRenderProvider", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Fixture playback error"])
    }
  }
}
