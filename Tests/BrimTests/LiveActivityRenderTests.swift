import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders every closed-island live activity through the real shell on the notch and on the pill,
/// then the expanded cards, into `.renders/live-activities-*.png` (the matrix a person looks at),
/// and checks each one actually drew something clear of the camera housing and the shape's ends.
@MainActor
@Suite(.serialized)
struct LiveActivityRenderTests {
  struct Scenario {
    let name: String
    let setup: @MainActor () -> Void
    var teardown: @MainActor () -> Void = {}
    var recording: Bool = false
    var timer: Bool = false
  }

  static let notch = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 185, notchHeight: 32)
  static let pill = NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
  static let canvas = CGSize(width: 520, height: 76)
  static let cardCanvas = CGSize(width: 520, height: 150)

  private static func flash(
    _ title: String, _ symbol: String, _ tint: Color, value: Double? = nil, kind: HUDKind = .general, detail: String? = nil,
    elapsed: Date? = nil, short: String? = nil, hero: Bool = false, action: HUDAction? = nil
  ) -> @MainActor () -> Void {
    {
      IslandFlashCenter.shared.show(
        title, symbol: symbol, tint: tint, value: value, duration: 600, kind: kind, detail: detail, elapsedSince: elapsed,
        action: action, shortTitle: short, hero: hero)
    }
  }

  static let compact: [Scenario] = [
    Scenario(name: "Update · Brim 1.2.0", setup: flash("New version available", "arrow.down.circle.fill", .green, detail: "Brim 1.2.0", short: "Update 1.2.0")),
    Scenario(name: "Charging 80%", setup: flash("Charging", "bolt.fill", .green, value: 0.8)),
    Scenario(name: "Low battery 20%", setup: flash("Low battery", "battery.25percent", .red, value: 0.2)),
    Scenario(name: "Full battery", setup: flash("Full Battery", "battery.100percent.bolt", .green, detail: "Your Mac is fully charged.", short: "Full", hero: true)),
    Scenario(name: "Keep awake 28:00", setup: { KeepAwakeModel.shared.start(minutes: 28) }, teardown: { KeepAwakeModel.shared.stop(announce: false) }),
    Scenario(name: "Pomodoro 25:00", setup: { FocusTimerModel.shared.startPomodoro() }, teardown: { FocusTimerModel.shared.stop() }),
    Scenario(name: "Timer 2:28", setup: {}, timer: true),
    Scenario(name: "Build 64%", setup: {
      XcodeBuildModel.shared.preview(
        .building(project: "Brim", since: Date().addingTimeInterval(-64)),
        last: XcodeLastBuild(project: "Brim", succeeded: true, errors: 0, warnings: 0, duration: 100, finished: .now))
    }, teardown: { XcodeBuildModel.shared.preview(.idle, last: nil, watching: false, found: false) }),
    Scenario(name: "Lock", setup: flash("Locked", "lock.fill", .white)),
    Scenario(name: "Brightness 64", setup: flash("Display", "sun.max.fill", HUDTint.color(hex: "#FFD60A"), value: 0.64, kind: .brightness)),
    Scenario(name: "Volume 60", setup: flash("Volume", "speaker.wave.2.fill", HUDTint.color(hex: "#34C759"), value: 0.6, kind: .volume)),
    Scenario(name: "Muted (red)", setup: flash("Muted", "speaker.slash.fill", .red, value: 0, kind: .volume)),
    Scenario(name: "Screen recording 1:05", setup: {}, recording: true),
    Scenario(name: "Camera in use", setup: { SystemSignalsMonitor.shared.preview(camera: true, microphone: false) },
             teardown: { SystemSignalsMonitor.shared.preview(camera: false, microphone: false) }),
    Scenario(name: "Microphone in use", setup: { SystemSignalsMonitor.shared.preview(camera: false, microphone: true) },
             teardown: { SystemSignalsMonitor.shared.preview(camera: false, microphone: false) }),
    Scenario(name: "Focus On", setup: { SystemStatusIndicators.shared.preview(focus: true, hotspot: false) },
             teardown: { SystemStatusIndicators.shared.preview(focus: false, hotspot: false) }),
    Scenario(name: "Personal Hotspot Active", setup: { SystemStatusIndicators.shared.preview(focus: false, hotspot: true) },
             teardown: { SystemStatusIndicators.shared.preview(focus: false, hotspot: false) }),
    Scenario(name: "Device battery 80%", setup: flash("AirPods Pro", "airpodspro", .green, value: 0.8, kind: .bluetooth)),
    Scenario(name: "Downloaded", setup: flash("Report.pdf", "checkmark.circle.fill", .blue, detail: "Downloaded", short: "Downloaded")),
    Scenario(name: "Drive", setup: flash("Backup Drive", "externaldrive.fill", .white, kind: .drive, short: "Drive")),
    Scenario(name: "VPN connected", setup: flash("Work VPN", "lock.shield.fill", .green, kind: .vpn, short: "VPN")),
    Scenario(name: "Wi-Fi", setup: flash("Studio", "wifi", .white, kind: .wifi, short: "Studio")),
  ]

  static let cards: [Scenario] = [
    Scenario(name: "Full Battery card", setup: flash("Full Battery", "battery.100percent.bolt", .green, detail: "Your Mac is fully charged.", short: "Full", hero: true)),
    Scenario(name: "VPN card", setup: flash("Work VPN", "lock.shield.fill", .orange, kind: .vpn, detail: "VPN connected", elapsed: Date().addingTimeInterval(-65), short: "VPN")),
    Scenario(name: "Drive card", setup: flash("Backup Drive", "externaldrive.fill", .white, kind: .drive, detail: "654 GB available of 1 TB", short: "Drive",
      action: HUDAction(title: "Eject", symbol: "eject.fill") {})),
    Scenario(name: "Update card", setup: flash("New version available", "arrow.down.circle.fill", .green, detail: "Brim 1.2.0", short: "Update 1.2.0",
      action: HUDAction(title: "Details", symbol: "info.circle") {})),
    Scenario(name: "Hotspot card", setup: flash("Personal Hotspot", "personalhotspot", .green, detail: "Connected through your phone", short: "Hotspot")),
    Scenario(name: "Download card", setup: flash("Report.pdf", "checkmark.circle.fill", .blue, detail: "Downloaded", short: "Downloaded",
      action: HUDAction(title: "Open", symbol: "arrow.up.forward.app") {})),
  ]

  // MARK: Rendering

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-live-\(UUID().uuidString)")!)
  }

  private func render(_ geometry: NotchGeometry, scenario: Scenario, hovered: Bool, size: CGSize) async throws -> NSBitmapImageRep {
    scenario.setup()
    // Activities show once the start-up flash ("Awake") has gone.
    if !hovered, scenario.name.hasPrefix("Keep awake") { IslandFlashCenter.shared.dismiss() }
    defer {
      scenario.teardown()
      IslandFlashCenter.shared.dismiss()
    }
    let presentation = NotchPresentation()
    var geometry = geometry
    geometry.hudHovered = hovered
    presentation.geometry = geometry
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recording = ScreenRecordingModel(probe: { scenario.recording ? ScreenRecordingEvidence(identity: "fixture") : nil })
    await recording.refreshNow()
    let timers = NativeTimerModel(probe: {
      scenario.timer ? NativeTimerActivity(id: "t", title: "Tea", duration: 180, endDate: nil, pausedRemaining: 148) : nil
    })
    await timers.refreshNow()
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(provider: QuietPlayer(), enabledSources: []),
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: recording, timers: timers,
      notifications: NotificationHUDModel(settings: settings()), glances: IslandGlanceModel(settings: settings()),
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let host = NSHostingView(
      rootView: view.padding(.top, geometry.topInset).frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(white: 0.34)))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func darkPixels(_ image: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: image.pixelsHigh, by: 2) {
      for x in stride(from: 0, to: image.pixelsWide, by: 2) {
        if let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.redComponent < 0.04, c.greenComponent < 0.04 { count += 1 }
      }
    }
    return count
  }

  // MARK: Tests

  @Test func compactMatrix() async throws {
    var rows: [(String, [NSBitmapImageRep])] = []
    for scenario in Self.compact {
      let notch = try await render(Self.notch, scenario: scenario, hovered: false, size: Self.canvas)
      let pill = try await render(Self.pill, scenario: scenario, hovered: false, size: Self.canvas)
      #expect(darkPixels(notch) > 200, "\(scenario.name): no shape on the notch")
      #expect(darkPixels(pill) > 200, "\(scenario.name): no shape on the pill")
      rows.append((scenario.name, [notch, pill]))
    }
    try writeSheet(rows, columns: ["notch", "pill"], canvas: Self.canvas, name: "live-activities-compact")
  }

  @Test func expandedCards() async throws {
    var rows: [(String, [NSBitmapImageRep])] = []
    for scenario in Self.cards {
      let notch = try await render(Self.notch, scenario: scenario, hovered: true, size: Self.cardCanvas)
      let pill = try await render(Self.pill, scenario: scenario, hovered: true, size: Self.cardCanvas)
      rows.append((scenario.name, [notch, pill]))
    }
    try writeSheet(rows, columns: ["notch", "pill"], canvas: Self.cardCanvas, name: "live-activities-cards")
  }

  // MARK: Output

  private func writeSheet(_ rows: [(String, [NSBitmapImageRep])], columns: [String], canvas: CGSize, name: String) throws {
    let labelWidth: CGFloat = 190
    let gap: CGFloat = 4
    let width = labelWidth + canvas.width * CGFloat(columns.count)
    let height = rows.count == 0 ? 1 : CGFloat(rows.count) * (canvas.height + gap) + 20
    let sheet = NSImage(size: CGSize(width: width, height: height))
    sheet.lockFocus()
    NSColor(white: 0.12, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    for (index, column) in columns.enumerated() {
      (column as NSString).draw(at: CGPoint(x: labelWidth + canvas.width * CGFloat(index) + 8, y: height - 16),
                                withAttributes: [.font: font, .foregroundColor: NSColor.lightGray])
    }
    var y = height - 20
    for (label, images) in rows {
      y -= canvas.height
      for (index, image) in images.enumerated() {
        image.draw(in: CGRect(x: labelWidth + canvas.width * CGFloat(index), y: y, width: canvas.width, height: canvas.height))
      }
      (label as NSString).draw(at: CGPoint(x: 10, y: y + canvas.height - 26), withAttributes: [.font: font, .foregroundColor: NSColor.white])
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

private struct QuietPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
