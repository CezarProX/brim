import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the split island through the real shell: a song on the island, a Claude agent in the left
/// bubble and a timer in the right one, on a MacBook notch and on the floating pill of an external
/// display, closed and open. Then the bubbles on their own, large, in every state. Sheets land in
/// `.renders/bubbles-*.png`.
@MainActor
@Suite(.serialized)
struct IslandBubbleRenderTests {
  enum Surface: String, CaseIterable {
    case notch = "notch 1512x982", simulated = "simulated notch 1920x1080", pill = "pill 1920x1080"

    func geometry() -> NotchGeometry {
      switch self {
      case .notch:
        return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 185, notchHeight: 32)
      case .simulated:
        return NotchGeometry.simulatedExternal(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
      case .pill:
        return NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
      }
    }
  }

  private static let canvas = CGSize(width: 560, height: 60)
  private static let background = NSColor(white: 0.34, alpha: 1)

  private struct Player: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
      NowPlayingSnapshot(source: .music, title: "Midnight City", artist: "M83", album: "Hurry Up",
                         duration: 243, position: 96, isPlaying: true)
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }

  private static func artworkPNG() -> Data? {
    let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
      NSGradient(colors: [NSColor(red: 0.98, green: 0.35, blue: 0.45, alpha: 1),
                          NSColor(red: 0.35, green: 0.2, blue: 0.85, alpha: 1)])?.draw(in: rect, angle: 55)
      NSColor.white.withAlphaComponent(0.85).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 96, dy: 96)).fill()
      return true
    }
    return try? ImageEncoder.pngDataPreservingAlpha(from: image)
  }

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-bubbles-\(UUID().uuidString)")!)
  }

  private func agentSession(_ state: CodingAgentSession.State) -> CodingAgentSession {
    CodingAgentSession(tool: .claude, model: nil, state: state, steps: [], lastMessage: nil, outputTokens: 0,
                       contextTokens: 0, turns: 1, started: nil, updated: .now)
  }

  /// The real shell with music, a 24-minute timer and a working agent.
  private func renderScene(_ surface: Surface, expanded: Bool, wideHome: Bool = false) async throws -> (NSBitmapImageRep, NotchPresentation, CGSize) {
    CodingAgentModel.shared.setSessionsForPreview([agentSession(.running("Bash"))])
    defer { CodingAgentModel.shared.setSessionsForPreview([]) }
    let presentation = NotchPresentation()
    var geometry = surface.geometry()
    if wideHome { geometry.tuning.openScale = 1.18 }
    presentation.homeTapped = wideHome
    presentation.geometry = geometry
    presentation.isExpanded = expanded
    let artwork = Self.artworkPNG()
    let music = NowPlayingModel(provider: Player(), enabledSources: [.music], artworkLoader: { _ in artwork }, stream: nil)
    await music.refreshNow()
    let timer = NativeTimerActivity(id: "fixture", title: "Pasta", duration: 30 * 60,
                                    endDate: Date().addingTimeInterval(24 * 60 + 10), pausedRemaining: nil)
    let timers = NativeTimerModel(probe: { timer })
    await timers.refreshNow()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let size = wideHome ? geometry.hostingFrame.size : expanded ? CGSize(width: 860, height: 420) : Self.canvas
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory), nowPlaying: music,
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: timers, homeWidgets: HomeWidgetStore(widgets: [.media, .captures], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()),
      glances: IslandGlanceModel(settings: settings()), theme: IslandTheme(surface: .black),
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let host = NSHostingView(
      rootView: view.padding(.top, geometry.topInset).frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(nsColor: Self.background)))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
                          defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1200))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return (bitmap, presentation, size)
  }

  @Test func splitIslandOnEverySurface() async throws {
    var rows: [(String, NSImage)] = []
    for surface in Surface.allCases {
      for expanded in [false, true] {
        let (bitmap, presentation, size) = try await renderScene(surface, expanded: expanded)
        let geometry = presentation.geometry
        #expect(presentation.bubbleActivity(.leading) == .agent, "\(surface): agent on the left")
        #expect(presentation.bubbleActivity(.trailing) == .timer, "\(surface): timer on the right")
        #expect(geometry.hasLeadingBubble && geometry.hasSecondaryActivity, "\(surface) expanded \(expanded)")
        checkBubbles(bitmap, geometry: geometry, size: size, expanded: expanded, label: surface.rawValue)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        rows.append(("\(surface.rawValue)\(expanded ? " · open" : "")", image))
      }
    }
    try writeSheet(rows, name: "bubbles-island")
  }

  @Test func wideHomeBubblesRenderInsideTheNativeCanvas() async throws {
    var rows: [(String, NSImage)] = []
    for surface in Surface.allCases {
      let (bitmap, presentation, size) = try await renderScene(surface, expanded: true, wideHome: true)
      checkBubbles(bitmap, geometry: presentation.geometry, size: size, expanded: true, label: surface.rawValue)
      let image = NSImage(size: size)
      image.addRepresentation(bitmap)
      rows.append((surface.rawValue, image))
    }
    try writeSheet(rows, name: "bubbles-wide-home-native")
  }

  /// Each bubble black and round where the geometry says, a clear gap to the island, and nothing
  /// drawn past it.
  private func checkBubbles(_ bitmap: NSBitmapImageRep, geometry: NotchGeometry, size: CGSize, expanded: Bool,
                            label: String) {
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
      bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB)
    }
    // The canvas's grey as it came out of the bitmap (colour-space conversion shifts it).
    let grey = pixel(2, size.height - 2)?.brightnessComponent ?? 0.34
    for side in IslandBubbleSide.allCases {
      let frame = geometry.bubbleFrame(side, expanded: expanded)
      // Screen to canvas: the canvas is centred on the display, its top at the display's top edge.
      let x = frame.minX - geometry.screenFrame.midX + size.width / 2
      let y = geometry.screenFrame.maxY - frame.maxY
      let r = frame.width / 2
      // Black just inside the rim (outside the ring), on the side away from the island.
      let rim = side == .leading ? pixel(x + 1.2, y + r) : pixel(x + frame.width - 1.2, y + r)
      #expect((rim?.brightnessComponent ?? 1) < 0.12, "\(label) \(side): bubble not black at its rim")
      // Corners of the square are background: the bubble is a circle, not a capsule.
      let corner = pixel(x + 1, y + frame.height - 1)
      #expect(abs((corner?.brightnessComponent ?? 0) - grey) < 0.04, "\(label) \(side): bubble corner filled")
      // The gap to the island is background.
      let gapX = side == .leading ? x + frame.width + NotchGeometry.bubbleGap / 2 : x - NotchGeometry.bubbleGap / 2
      let gap = pixel(gapX, y + r)
      #expect(abs((gap?.brightnessComponent ?? 0) - grey) < 0.04, "\(label) \(side): no gap between bubble and island")
      // Past the bubble: background.
      let outX = side == .leading ? x - 3 : x + frame.width + 3
      let outside = pixel(outX, y + r)
      #expect(abs((outside?.brightnessComponent ?? 0) - grey) < 0.04, "\(label) \(side): ink past the bubble")
      // Something is drawn in the middle (glyph or readout).
      var lit = 0
      for dy in stride(from: -r * 0.5, through: r * 0.5, by: 1) {
        for dx in stride(from: -r * 0.5, through: r * 0.5, by: 1) {
          if (pixel(x + r + dx, y + r + dy)?.brightnessComponent ?? 0) > 0.4 { lit += 1 }
        }
      }
      #expect(lit > 4, "\(label) \(side): empty bubble")
    }
  }

  // MARK: Bubbles up close

  private func bubble<Content: View>(_ diameter: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
    content().frame(width: diameter, height: diameter).background(.black, in: Circle())
  }

  private func closeUp(_ diameter: CGFloat) -> some View {
    let artwork = Self.artworkPNG().flatMap(NSImage.init(data:))
    return HStack(spacing: 14) {
      bubble(diameter) { TimerBubble(remaining: 24 * 60 + 10, duration: 30 * 60, paused: false, diameter: diameter) }
      bubble(diameter) { TimerBubble(remaining: 2 * 3600 + 300, duration: 3 * 3600, paused: false, diameter: diameter) }
      bubble(diameter) { TimerBubble(remaining: 8 * 60 + 1, duration: 10 * 60, paused: true, diameter: diameter) }
      bubble(diameter) { TimerBubble(remaining: 42, duration: 5 * 60, paused: false, diameter: diameter) }
      bubble(diameter) { TimerBubble(remaining: 0, duration: 5 * 60, paused: false, done: true, diameter: diameter) }
      bubble(diameter) { AgentBubble(tool: .claude, state: .working, diameter: diameter) }
      bubble(diameter) { AgentBubble(tool: .claude, state: .needsInput, diameter: diameter) }
      bubble(diameter) { AgentBubble(tool: .codex, state: .finished, diameter: diameter) }
      bubble(diameter) { MusicBubble(artwork: artwork, isPlaying: true, diameter: diameter) }
      bubble(diameter) { DownloadBubble(fraction: 0.62, diameter: diameter) }
      bubble(diameter) { Circle().fill(IslandTint.recording).frame(width: 11, height: 11) }
    }
    .padding(12)
    .background(Color(nsColor: Self.background))
    .environment(\.colorScheme, .dark)
  }

  @Test func bubbleStatesUpClose() throws {
    var rows: [(String, NSImage)] = []
    for (name, diameter) in [("notch · 32pt", CGFloat(32)), ("pill · 37pt", CGFloat(37))] {
      let renderer = ImageRenderer(content: closeUp(diameter))
      renderer.scale = 6
      // Drawn three times larger in the sheet, so the details can be judged.
      let cgImage = try #require(renderer.cgImage)
      let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
      rows.append(("\(name): timer 24m · 2h · paused · last minute · done | agent working · needs you · finished | music | download | recording",
                   image))
    }
    try writeSheet(rows, name: "bubbles-states", labelAbove: true)
  }

  // MARK: Output

  private func writeSheet(_ rows: [(String, NSImage)], name: String, labelAbove: Bool = false) throws {
    let gap: CGFloat = 8
    let labelHeight: CGFloat = labelAbove ? 22 : 0
    let labelWidth: CGFloat = labelAbove ? 0 : 230
    let width = (rows.map { $0.1.size.width }.max() ?? 0) + labelWidth
    let height = rows.reduce(CGFloat(0)) { $0 + $1.1.size.height + gap + labelHeight }
    let sheet = NSImage(size: CGSize(width: width, height: height))
    sheet.lockFocus()
    NSColor(white: 0.12, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    var y = height
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: labelAbove ? 14 : 12, weight: .medium), .foregroundColor: NSColor.white,
    ]
    for (label, image) in rows {
      if labelAbove {
        y -= labelHeight
        (label as NSString).draw(at: CGPoint(x: 8, y: y + 3), withAttributes: attributes)
      }
      y -= image.size.height
      image.draw(in: CGRect(x: labelWidth, y: y, width: image.size.width, height: image.size.height))
      if !labelAbove {
        (label as NSString).draw(at: CGPoint(x: 10, y: y + image.size.height - 26), withAttributes: attributes)
      }
      y -= gap
    }
    sheet.unlockFocus()
    let tiff = try #require(sheet.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
