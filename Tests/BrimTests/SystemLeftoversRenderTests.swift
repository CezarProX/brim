import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the changed settings and island pieces to `.renders/` so they can be looked at.
@MainActor
@Suite(.serialized)
struct SystemLeftoversRenderTests {
  private func outputDir() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func shoot<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = false) async throws {
    let host = NSHostingView(rootView: view.preferredColorScheme(dark ? .dark : .light))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(500))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: try outputDir().appendingPathComponent("\(name).png"))
    #expect(png.count > 3_000)
  }

  @Test func shortcutsPane() async throws {
    try await shoot(ShortcutSettingsView(), size: CGSize(width: 620, height: 760), name: "system-shortcuts")
  }

  @Test func updatesAndBluetoothSections() async throws {
    try await shoot(UpdatesSettingsSection().padding(20), size: CGSize(width: 560, height: 260), name: "system-updates")
    try await shoot(BluetoothDevicesSettingsSection().padding(20), size: CGSize(width: 560, height: 140), name: "system-bluetooth-empty")
  }

  @Test func statsWithSparklines() async throws {
    var history = StatsHistory()
    for index in 0..<40 {
      let t = Double(index) / 6
      history.record(cpu: 0.4 + 0.3 * sin(t), memory: 0.6 + 0.05 * sin(t / 2), gpu: nil,
                     down: 400_000 + 300_000 * sin(t * 1.3), up: 80_000)
    }
    let input = StatsCardReading.Input(cpu: 0.55, memoryUsed: 10 << 30, memoryTotal: 16 << 30,
                                       networkDown: 600_000, networkUp: 80_000)
    let row = HStack(spacing: 8) {
      StatsCardView(reading: .make(.cpu, input), history: history.series(for: .cpu))
      StatsCardView(reading: .make(.ram, input), history: history.series(for: .ram))
      StatsCardView(reading: .make(.network, input), history: history.series(for: .network))
    }
    .padding(14).frame(width: 460).background(Color.black)
    try await shoot(row, size: CGSize(width: 460, height: 190), name: "system-stats-sparklines", dark: true)
  }

  @Test func dictationCompactTrailing() async throws {
    let view = HStack {
      Image(systemName: "mic.fill").foregroundStyle(.blue)
      Spacer()
      Text(DictationCompactLine.tail("so the plan for tomorrow is to ship the new island")).foregroundStyle(.white)
    }
    .padding(10).frame(width: 300).background(Capsule().fill(.black))
    try await shoot(view.padding(10).background(Color.gray), size: CGSize(width: 320, height: 60), name: "system-dictation-compact", dark: true)
  }
}
