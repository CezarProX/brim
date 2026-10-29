import AppKit
import SwiftUI

/// Fixture data for the tour's live renders: the real views, fed sample content. Nothing here reads
/// the user's files, accounts or permissions.
enum OnboardingSamples {
  private actor Provider: NowPlayingProviding {
    let value: NowPlayingSnapshot
    init(_ value: NowPlayingSnapshot) { self.value = value }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { value }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }

  /// A playing fixture song with generated artwork, isolated from the user's real player.
  @MainActor
  static func nowPlaying() async -> NowPlayingModel {
    let snapshot = NowPlayingSnapshot(
      source: .music, title: "Blue Hour", artist: "Nova Coast", album: "Night Drive", duration: 214, position: 71,
      isPlaying: true, artworkData: coverData(seed: 0, size: 256), isFavorite: false)
    let model = NowPlayingModel(provider: Provider(snapshot), enabledSources: [.music], stream: nil)
    await model.refreshNow()
    for _ in 0..<100 where model.track?.artwork == nil { try? await Task.sleep(for: .milliseconds(20)) }
    return model
  }

  static func artworkData() -> Data? { coverData(seed: 0, size: 256) }

  // MARK: Covers

  private static let palettes: [[(CGFloat, CGFloat, CGFloat)]] = [
    [(0.99, 0.46, 0.34), (0.60, 0.22, 0.62), (0.16, 0.12, 0.45)],
    [(0.30, 0.82, 0.88), (0.16, 0.38, 0.86), (0.08, 0.10, 0.40)],
    [(1.00, 0.80, 0.36), (0.95, 0.38, 0.45), (0.40, 0.16, 0.50)],
    [(0.56, 0.92, 0.62), (0.12, 0.58, 0.58), (0.05, 0.20, 0.34)],
    [(0.94, 0.62, 0.92), (0.46, 0.34, 0.92), (0.10, 0.12, 0.42)],
    [(0.98, 0.92, 0.80), (0.86, 0.52, 0.38), (0.30, 0.18, 0.30)],
  ]

  /// Colourful generated album art: a gradient sky, a sun or moon, and layered waves.
  static func coverData(seed: Int, size: Int) -> Data? {
    guard let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let palette = palettes[((seed % palettes.count) + palettes.count) % palettes.count]
    let colors = palette.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    let s = CGFloat(size)
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.55, 1]) {
      context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s * 0.4, y: 0), options: [])
    }
    let sunX = s * (0.3 + 0.4 * CGFloat((seed * 37) % 10) / 10)
    context.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.82, alpha: 0.92))
    context.fillEllipse(in: CGRect(x: sunX - s * 0.16, y: s * 0.52, width: s * 0.32, height: s * 0.32))
    for layer in 0..<3 {
      let base = s * (0.34 - CGFloat(layer) * 0.1)
      let path = CGMutablePath()
      path.move(to: CGPoint(x: 0, y: 0))
      path.addLine(to: CGPoint(x: 0, y: base))
      path.addCurve(
        to: CGPoint(x: s, y: base + s * 0.04), control1: CGPoint(x: s * 0.3, y: base + s * (0.14 + 0.03 * CGFloat(seed % 3))),
        control2: CGPoint(x: s * 0.62, y: base - s * 0.12))
      path.addLine(to: CGPoint(x: s, y: 0))
      path.closeSubpath()
      let shade = 0.55 - CGFloat(layer) * 0.17
      context.setFillColor(CGColor(red: palette[2].0 * shade, green: palette[2].1 * shade, blue: palette[2].2 * shade + 0.1, alpha: 0.78))
      context.addPath(path)
      context.fillPath()
    }
    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }

  /// The "Playing Next" list, answered by a fixture instead of Apple Music.
  @MainActor
  static func queue() -> PlayingNextModel {
    let rows: [(String, String, Int)] = [
      ("Low Tide", "Harbor Lights", 198), ("Paper Planes", "The Quiet Hours", 231), ("Glass Garden", "Oma Vale", 187),
      ("Afterglow", "Nova Coast", 242), ("Slow Signals", "Kite & Key", 205),
    ]
    let separator = String(QueueParsing.fieldSeparator)
    let output = rows.enumerated().map { offset, row in
      ["\(offset + 2)", "fixture-\(offset)", row.0, row.1, "\(row.2)"].joined(separator: separator)
    }.joined(separator: "\n")
    return PlayingNextModel(
      read: { _ in output }, perform: { _ in "" },
      fetchArtwork: { index in coverData(seed: index, size: 96) })
  }

  /// A Playing Next model that never reads the real player.
  @MainActor
  static func emptyQueue() -> PlayingNextModel {
    PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil })
  }

  // MARK: Files

  struct TrayFiles {
    let directory: URL
    let photo: URL
    let all: [URL]
  }

  /// Real files in a temp folder, so Finder-quality thumbnails and icons come from the system.
  static func makeFiles() -> TrayFiles {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("BrimTour", isDirectory: true)
    try? manager.removeItem(at: directory)
    let files = directory.appendingPathComponent("Files", isDirectory: true)
    try? manager.createDirectory(at: files, withIntermediateDirectories: true)
    let photo = files.appendingPathComponent("Tahoe.jpg")
    if let png = coverData(seed: 1, size: 640), let image = NSBitmapImageRep(data: png),
      let jpeg = image.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
      try? jpeg.write(to: photo)
    }
    let brief = files.appendingPathComponent("Brief.pdf")
    writeBrief(to: brief)
    let notes = files.appendingPathComponent("Notes.txt")
    try? "Moved the review to 3 pm. Same room, bring the new designs.".write(to: notes, atomically: true, encoding: .utf8)
    let folder = files.appendingPathComponent("Invoices", isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    return TrayFiles(directory: directory, photo: photo, all: [photo, brief, notes, folder])
  }

  private static func writeBrief(to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 420, height: 560)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    context.beginPDFPage(nil)
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    NSAttributedString(string: "Project brief", attributes: [.font: NSFont.boldSystemFont(ofSize: 26)])
      .draw(at: CGPoint(x: 36, y: 490))
    let body = "Goals, timeline and owners for the autumn release.\nShip the redesign, keep the notch calm, and make the first run delightful."
    NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.darkGray])
      .draw(in: CGRect(x: 36, y: 380, width: 348, height: 90))
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
  }

  /// A tray holding the sample files; it lives in the temp folder and never touches the real tray.
  @MainActor
  static func trayStore(_ files: TrayFiles) -> FileTrayStore {
    let store = FileTrayStore(directory: files.directory.appendingPathComponent("Tray", isDirectory: true))
    _ = store.add(files.all)
    return store
  }

  // MARK: Clipboard

  static func clipboardEntries(now: Date = .now) -> [ClipboardEntry] {
    [
      ClipboardEntry(
        id: UUID(), date: now.addingTimeInterval(-120), kind: .text, text: "Moved the review to 3 pm. Same room, bring the new designs.",
        fingerprint: "tour-text", byteCount: 59, pixelSize: nil, copies: 1),
      ClipboardEntry(
        id: UUID(), date: now.addingTimeInterval(-900), kind: .link, text: "https://developer.apple.com/design",
        fingerprint: "tour-link", byteCount: 34, pixelSize: nil, copies: 2),
      ClipboardEntry(
        id: UUID(), date: now.addingTimeInterval(-3600), kind: .color, text: "#5B4CF0", fingerprint: "tour-color", byteCount: 7,
        pixelSize: nil, copies: 1),
    ]
  }

  /// The sample history as a store of its own, in a temp folder on a private pasteboard, so the
  /// tour's Clipboard page never reads or writes the user's history or clipboard.
  @MainActor
  static func clipboardStore(_ entries: [ClipboardEntry]) -> ClipboardStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BrimTourClipboard", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(entries) {
      try? data.write(to: directory.appendingPathComponent("entries.json"))
    }
    return ClipboardStore(directory: directory, pasteboard: NSPasteboard(name: NSPasteboard.Name("io.github.cezarprox.brim.tour")))
  }

  // MARK: Misc

  static func statsInput() -> StatsCardReading.Input {
    var input = StatsCardReading.Input()
    input.cpu = 0.27
    input.memoryUsed = 11 << 30
    input.memoryTotal = 24 << 30
    input.diskFree = 310_000_000_000
    input.diskTotal = 500_000_000_000
    input.networkDown = 2_400_000
    input.networkUp = 180_000
    input.batteryPercent = 82
    return input
  }

  static func upcoming(now: Date = .now) -> [CalendarAgendaItem] {
    [CalendarAgendaItem(id: "sample", kind: .event, title: "Design review", start: now.addingTimeInterval(25 * 60),
                        end: now.addingTimeInterval(85 * 60), isAllDay: false, color: .red, joinURL: nil)]
  }

  static func meeting(now: Date = .now) -> CalendarMeeting {
    CalendarMeeting(id: "tour", title: "Design review", startsAt: now.addingTimeInterval(4 * 60), endsAt: now.addingTimeInterval(64 * 60),
                    calendar: "Work", joinURL: nil)
  }

  static func weather(now: Date = .now) -> WeatherSnapshot {
    WeatherSnapshot(place: "Cupertino", fetched: now, celsius: 21, feelsLikeCelsius: 20, code: 1, isDay: true,
                    highCelsius: 24, lowCelsius: 14, hours: [])
  }
}
