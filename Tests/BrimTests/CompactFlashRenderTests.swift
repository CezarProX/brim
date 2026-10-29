import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the closed island's flashes through the real shell (`NotchShelfView` + `IslandFlashCenter`)
/// on a MacBook notch (1512×982, 185×32 housing) and on the floating pill of 1920×1080 and
/// 3440×1440 externals, then checks the pixels: every glyph and label sits inside the black shape,
/// clear of its rounded ends, never under the camera housing, centred in its wing on the notch and
/// balanced on the pill. Sheets land in `.renders/compact-flashes-*.png` and `compact-hud-cards.png`.
@MainActor
@Suite(.serialized)
struct CompactFlashRenderTests {
  enum Surface: String {
    case notch = "notch 1512x982", fhd = "pill 1920x1080", ultrawide = "pill 3440x1440"

    func geometry() -> NotchGeometry {
      switch self {
      case .notch:
        return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 185, notchHeight: 32)
      case .fhd:
        return NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
      case .ultrawide:
        return NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 1512, y: 0, width: 3440, height: 1440))
      }
    }
  }

  struct Flash {
    let name: String
    let show: @MainActor () -> Void
  }

  static let flashes: [Flash] = [
    Flash(name: "Kept 1 file") {
      IslandFlashCenter.shared.show("Kept 1 file", symbol: "tray.and.arrow.down.fill", tint: .blue, duration: 600)
    },
    Flash(name: "Copied 3 files") {
      IslandFlashCenter.shared.show("Copied 3 files", symbol: "doc.on.doc.fill", tint: .green, duration: 600)
    },
    Flash(name: "Converted to PNG") {
      IslandFlashCenter.shared.show("Converted to PNG", symbol: "checkmark.circle.fill", tint: .green, duration: 600)
    },
    Flash(name: "AirDrop unavailable") {
      IslandFlashCenter.shared.show("AirDrop unavailable", symbol: "dot.radiowaves.left.and.right", tint: .white,
                                    duration: 600)
    },
    Flash(name: "Long title") {
      IslandFlashCenter.shared.show("Turn on Menu Bar Manager in Settings", symbol: "menubar.rectangle", tint: .orange,
                                    duration: 600)
    },
    Flash(name: "Volume 40%") {
      IslandFlashCenter.shared.show("Volume", symbol: HUDSymbol.volume(level: 0.4, muted: false),
                                    tint: HUDTint.color(hex: "#34C759"), value: 0.4, duration: 600, kind: .volume)
    },
    Flash(name: "Brightness 75%") {
      IslandFlashCenter.shared.show("Display", symbol: HUDSymbol.brightness(level: 0.75),
                                    tint: HUDTint.color(hex: "#FFD60A"), value: 0.75, duration: 600, kind: .brightness)
    },
  ]

  private static let canvas = CGSize(width: 640, height: 76)
  private static let cardCanvas = CGSize(width: 640, height: 150)

  // MARK: Rendering

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-compact-\(UUID().uuidString)")!)
  }

  private func render(_ surface: Surface, hovered: Bool = false, size: CGSize,
                      notifications: NotificationHUDModel? = nil) async throws -> NSBitmapImageRep {
    let presentation = NotchPresentation()
    var geometry = surface.geometry()
    geometry.hudHovered = hovered
    presentation.geometry = geometry
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(provider: SilentPlayer(), enabledSources: []),
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), notifications: notifications ?? NotificationHUDModel(settings: settings()),
      glances: IslandGlanceModel(settings: settings()),
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let host = NSHostingView(
      rootView: view.padding(.top, geometry.topInset).frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(white: 0.34)))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
                          defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func cell(_ flash: Flash, on surface: Surface, hovered: Bool = false) async throws -> NSBitmapImageRep {
    flash.show()
    defer { IslandFlashCenter.shared.dismiss() }
    return try await render(surface, hovered: hovered, size: hovered ? Self.cardCanvas : Self.canvas)
  }

  /// Rows beyond the flashes that share the compact layout: a notification and a live activity.
  private func otherRows(on surface: Surface) async throws -> [(String, NSBitmapImageRep)] {
    let prefs = settings()
    prefs.notificationHUDEnabled = true
    let model = NotificationHUDModel(settings: prefs)
    model.ingest(NotificationContent(
      bundleID: "com.apple.MobileSMS", appName: "Messages", title: "Anna Kowalski",
      body: "Are we still on for dinner at 8?"))
    defer { model.stop() }
    let notification = try await render(surface, size: Self.canvas, notifications: model)
    CodingAgentModel.shared.setSessionsForPreview([
      CodingAgentSession(tool: .claude, model: nil, state: .needsInput("Approve: Bash"), steps: [],
                         lastMessage: nil, outputTokens: 0, contextTokens: 0, turns: 1, started: nil, updated: .now)
    ])
    defer { CodingAgentModel.shared.setSessionsForPreview([]) }
    let agent = try await render(surface, size: Self.canvas)
    return [("Notification", notification), ("Agent needs input", agent)]
  }

  // MARK: Tests

  @Test func flashesOnTheNotch() async throws {
    var rows: [(String, NSBitmapImageRep)] = []
    for flash in Self.flashes {
      let image = try await cell(flash, on: .notch)
      checkNotch(Ink(image, canvasWidth: Self.canvas.width), flash: flash.name, geometry: Surface.notch.geometry())
      rows.append(("\(flash.name) · notch", image))
    }
    for (name, image) in try await otherRows(on: .notch) {
      checkNotch(Ink(image, canvasWidth: Self.canvas.width), flash: name, geometry: Surface.notch.geometry())
      rows.append(("\(name) · notch", image))
    }
    try writeSheet(rows, name: "compact-flashes-notch")
  }

  @Test func flashesOnThePill() async throws {
    var rows: [(String, NSBitmapImageRep)] = []
    for flash in Self.flashes {
      let image = try await cell(flash, on: .fhd)
      checkPill(Ink(image, canvasWidth: Self.canvas.width), flash: flash.name, surface: .fhd)
      rows.append(("\(flash.name) · 1920", image))
    }
    for flash in Self.flashes.suffix(2) {
      let image = try await cell(flash, on: .ultrawide)
      checkPill(Ink(image, canvasWidth: Self.canvas.width), flash: flash.name, surface: .ultrawide)
      rows.append(("\(flash.name) · 3440", image))
    }
    for (name, image) in try await otherRows(on: .fhd) {
      checkPill(Ink(image, canvasWidth: Self.canvas.width), flash: name, surface: .fhd)
      rows.append(("\(name) · 1920", image))
    }
    try writeSheet(rows, name: "compact-flashes-pill")
  }

  /// The hover cards the volume and brightness strips grow into, on the notch and on both pills.
  @Test func levelCardsOnHover() async throws {
    var rows: [(String, NSBitmapImageRep)] = []
    for surface in [Surface.notch, .fhd, .ultrawide] {
      for flash in Self.flashes.suffix(2) {
        let image = try await cell(flash, on: surface, hovered: true)
        let ink = Ink(image, canvasWidth: Self.cardCanvas.width)
        let bounds = try #require(ink.bounds(), "\(flash.name) card on \(surface): no ink")
        // Content keeps clear of the card's rounded sides.
        #expect(ink.minEdgeClearance() >= 10, "\(flash.name) card on \(surface): ink \(ink.minEdgeClearance())pt from the edge")
        if surface != .notch {
          // No empty band at the top of the pill's card: the header starts near the top edge.
          #expect(bounds.minY - ink.shapeTop() <= 24, "\(flash.name) card on \(surface): header starts \(bounds.minY - ink.shapeTop())pt down")
        }
        rows.append(("\(flash.name) card · \(surface.rawValue)", image))
      }
    }
    try writeSheet(rows, name: "compact-hud-cards")
  }

  /// Short labels fit their wing whole: they are measured, not capped, and the wing has room.
  @Test func shortLabelsAreNeverCapped() {
    for text in ["Kept 1 file", "Copied 3 files", "Converted to PNG", "AirDrop unavailable", "Zipped", "Link copied"] {
      let width = CompactLayout.labelWidth(text, limit: CompactLayout.notchLabelLimit)
      #expect(width < CompactLayout.notchLabelLimit, "\(text) is capped at \(width)")
      var geometry = Surface.notch.geometry()
      geometry.route = .hud(IslandFlash(title: text, symbol: "tray.fill", tint: .blue, value: nil, until: .distantFuture))
      let wing = (geometry.collapsedSize.width - 2 * geometry.hudShoulder - geometry.notchWidth) / 2
      #expect(wing >= CompactLayout.wingOuter + width + CompactLayout.wingInner, "\(text): wing \(wing)")
    }
  }

  /// A notification's wings (notch) or pill grow with the measured sender, symmetric about the camera.
  @Test func notificationSizesToItsSender() {
    var notch = Surface.notch.geometry()
    notch.route = .notification
    notch.compactLabelWidth = CompactLayout.labelWidth("Anna Kowalski", limit: CompactLayout.notchLabelLimit)
    let wing = (notch.collapsedSize.width - notch.notchWidth) / 2
    #expect(wing == notch.closedShoulder + CompactLayout.wing(content: notch.compactLabelWidth))
    #expect(notch.collapsedMainOffset == 0)
    var pill = Surface.fhd.geometry()
    pill.route = .notification
    pill.compactLabelWidth = notch.compactLabelWidth
    #expect(pill.collapsedSize.width == max(NotchGeometry.islandClosedWidth, CompactLayout.pillWidth(content: notch.compactLabelWidth)))
  }

  /// The pill is a centred group sized to its content, never a split strip with a dead gap.
  @Test func pillStripFitsItsContent() {
    var geometry = Surface.fhd.geometry()
    geometry.route = .hud(IslandFlash(title: "Kept 1 file", symbol: "tray.fill", tint: .blue, value: nil, until: .distantFuture))
    let kept = geometry.collapsedSize.width
    geometry.route = .hud(IslandFlash(title: "AirDrop unavailable", symbol: "tray.fill", tint: .blue, value: nil,
                                      until: .distantFuture))
    #expect(geometry.collapsedSize.width > kept)
    #expect(kept >= NotchGeometry.islandClosedWidth)
    geometry.hudHovered = true
    #expect(geometry.collapsedSize.width >= HUDMetrics.pillCardWidth)
  }

  // MARK: Checks

  private func checkNotch(_ ink: Ink, flash: String, geometry: NotchGeometry) {
    guard let bounds = ink.bounds() else {
      Issue.record("\(flash): nothing drawn on the notch")
      return
    }
    let center = ink.canvasWidth / 2
    let camera = (center - geometry.notchWidth / 2 - 2)...(center + geometry.notchWidth / 2 + 2)
    #expect(!ink.any(inColumns: camera, maxY: geometry.notchHeight), "\(flash): ink under the camera housing")
    #expect(ink.minEdgeClearance() >= 10, "\(flash): ink \(ink.minEdgeClearance())pt from the shape's edge")
    #expect(bounds.minY >= 3 && bounds.maxY <= geometry.notchHeight - 3, "\(flash): ink rows \(bounds.minY)...\(bounds.maxY)")
    // Each wing's content hugs that wing's outer inset, so a short glyph opposite a long label sits as
    // far in from the left edge as the label does from the right (it used to float too far right).
    let edges = ink.shapeEdges(atY: geometry.notchHeight / 2)
    for (name, columns) in [("left", edges.left...(center - geometry.notchWidth / 2)),
                            ("right", (center + geometry.notchWidth / 2)...edges.right)] {
      guard let side = ink.bounds(inColumns: columns) else {
        Issue.record("\(flash): empty \(name) wing")
        continue
      }
      // `edges` is the visible side of the shape, so the outer inset is measured from there.
      let area = name == "left"
        ? (columns.lowerBound + CompactLayout.wingOuter)...(columns.upperBound - CompactLayout.wingInner)
        : (columns.lowerBound + CompactLayout.wingInner)...(columns.upperBound - CompactLayout.wingOuter)
      let offset = name == "left" ? side.minX - area.lowerBound : area.upperBound - side.maxX
      // Symbols carry a little transparent padding (the agent's hand, the speaker's waves): a few points of slack.
      #expect(offset >= -1 && offset <= 5, "\(flash): \(name) wing content is \(offset)pt in from its outer edge")
    }
  }

  private func checkPill(_ ink: Ink, flash: String, surface: Surface) {
    guard let bounds = ink.bounds() else {
      Issue.record("\(flash): nothing drawn on the pill (\(surface))")
      return
    }
    let edges = ink.shapeEdges(atY: ink.shapeTop() + NotchGeometry.islandHeight / 2)
    let left = bounds.minX - edges.left
    let right = edges.right - bounds.maxX
    #expect(left >= 16 && right >= 16, "\(flash) (\(surface)): margins \(left) / \(right)")
    #expect(abs(left - right) <= 6, "\(flash) (\(surface)): unbalanced margins \(left) / \(right)")
    #expect(ink.minEdgeClearance() >= 10, "\(flash) (\(surface)): ink \(ink.minEdgeClearance())pt from the rounded end")
    let top = ink.shapeTop()
    #expect(bounds.minY - top >= 5 && top + NotchGeometry.islandHeight - bounds.maxY >= 5,
            "\(flash) (\(surface)): ink rows \(bounds.minY)...\(bounds.maxY) in a band from \(top)")
  }

  // MARK: Output

  private func writeSheet(_ rows: [(String, NSBitmapImageRep)], name: String) throws {
    guard let first = rows.first?.1 else { return }
    let scale = CGFloat(first.pixelsWide) / Self.canvas.width
    let labelWidth: CGFloat = 270
    let gap: CGFloat = 6
    let width = labelWidth + Self.canvas.width
    let height = rows.reduce(CGFloat(0)) { $0 + CGFloat($1.1.pixelsHigh) / scale + gap }
    let sheet = NSImage(size: CGSize(width: width, height: height))
    sheet.lockFocus()
    NSColor(white: 0.12, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    var y = height
    for (label, image) in rows {
      let h = CGFloat(image.pixelsHigh) / scale
      y -= h
      image.draw(in: CGRect(x: labelWidth, y: y, width: CGFloat(image.pixelsWide) / scale, height: h))
      (label as NSString).draw(at: CGPoint(x: 10, y: y + h - 26), withAttributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
      ])
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

/// Pixel reading for one render. The shell is pure black on a mid-grey canvas; "ink" is any bright
/// pixel inside a row's black run (glyphs, labels, level bars), away from the anti-aliased rim.
/// Coordinates are in points, top-left origin.
private struct Ink {
  let canvasWidth: CGFloat
  private let scale: CGFloat
  private let width: Int
  private let height: Int
  private let luma: [Float]
  /// Ink pixels, with their distance (in points) to the nearest end of their row's black run.
  private let inkPixels: [(x: Int, y: Int, clearance: CGFloat)]
  private let runs: [(Int, Int)?]

  init(_ image: NSBitmapImageRep, canvasWidth: CGFloat) {
    self.canvasWidth = canvasWidth
    let width = image.pixelsWide
    let height = image.pixelsHigh
    let scale = CGFloat(width) / canvasWidth
    self.width = width
    self.height = height
    self.scale = scale
    var luma = [Float](repeating: 0, count: width * height)
    if image.bitsPerSample == 8, !image.isPlanar, image.samplesPerPixel >= 3, let data = image.bitmapData {
      let step = image.bitsPerPixel / 8
      // ARGB layouts put alpha in the first byte.
      let o = image.bitmapFormat.contains(.alphaFirst) && image.hasAlpha ? 1 : 0
      for y in 0..<height {
        let row = data + y * image.bytesPerRow
        for x in 0..<width {
          let p = row + x * step
          luma[y * width + x] = Float(max(p[o], p[o + 1], p[o + 2])) / 255
        }
      }
    } else {
      for y in 0..<height {
        for x in 0..<width {
          let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
          luma[y * width + x] = Float(max(c?.redComponent ?? 0, c?.greenComponent ?? 0, c?.blueComponent ?? 0))
        }
      }
    }
    self.luma = luma
    let black = { (x: Int, y: Int) in luma[y * width + x] < 0.04 }
    let runs: [(Int, Int)?] = (0..<height).map { y in
      guard let first = (0..<width).first(where: { black($0, y) }),
            let last = (0..<width).last(where: { black($0, y) }) else { return nil }
      return (first, last)
    }
    self.runs = runs
    var ink: [(x: Int, y: Int, clearance: CGFloat)] = []
    for y in 0..<height {
      guard let (first, last) = runs[y], last > first + 1 else { continue }
      for x in (first + 1)..<last where luma[y * width + x] > 0.3 {
        ink.append((x, y, CGFloat(min(x - first, last - x)) / scale))
      }
    }
    inkPixels = ink
  }

  private func run(_ y: Int) -> (Int, Int)? { runs[y] }

  func bounds(inColumns columns: ClosedRange<CGFloat>? = nil) -> CGRect? {
    let pixels = inkPixels.filter { pixel in columns.map { $0.contains(CGFloat(pixel.x) / scale) } ?? true }
    guard let minX = pixels.map(\.x).min(), let maxX = pixels.map(\.x).max(),
          let minY = pixels.map(\.y).min(), let maxY = pixels.map(\.y).max() else { return nil }
    return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                  width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
  }

  func any(inColumns columns: ClosedRange<CGFloat>, maxY: CGFloat) -> Bool {
    inkPixels.contains { columns.contains(CGFloat($0.x) / scale) && CGFloat($0.y) / scale < maxY }
  }

  /// The smallest distance from any ink pixel to the side of the shape on its own row.
  func minEdgeClearance() -> CGFloat { inkPixels.map(\.clearance).min() ?? .infinity }

  /// The first row the black shape covers.
  func shapeTop() -> CGFloat {
    CGFloat((0..<height).first { run($0) != nil } ?? 0) / scale
  }

  /// The shape's left and right edges on one row.
  func shapeEdges(atY y: CGFloat) -> (left: CGFloat, right: CGFloat) {
    let row = min(height - 1, max(0, Int(y * scale)))
    guard let (first, last) = run(row) else { return (0, 0) }
    return (CGFloat(first) / scale, CGFloat(last + 1) / scale)
  }
}

private struct SilentPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
