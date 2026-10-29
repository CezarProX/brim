import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the new widgets to PNGs under `.renders/` (git-ignored) so the design can be looked at,
/// and checks they actually draw something.
@MainActor
@Suite(.serialized)
struct WidgetsRenderTests {
  private static let base = Date(timeIntervalSince1970: 1_760_000_000)

  private func snapshot(code: Int, day: Bool, place: String = "San Francisco") -> WeatherSnapshot {
    let hours = (0..<8).map { index in
      WeatherHour(
        date: Self.base.addingTimeInterval(Double(index) * 3600), celsius: 17 - Double(index) * 0.7 + (day ? 3 : 0),
        code: index > 3 && code >= 61 ? 3 : code, isDay: day)
    }
    return WeatherSnapshot(
      place: place, fetched: Self.base, celsius: day ? 21.4 : 14.2, feelsLikeCelsius: 20, code: code, isDay: day,
      highCelsius: 23.6, lowCelsius: 12.1, hours: hours)
  }

  @Test func weatherCards() async throws {
    let cards = HStack(alignment: .top, spacing: 14) {
      WeatherCard(snapshot: snapshot(code: 1, day: true), unit: .fahrenheit).frame(width: 224, height: 132)
      WeatherCard(snapshot: snapshot(code: 0, day: false, place: "Reykjavík"), unit: .celsius).frame(width: 224, height: 132)
      WeatherCard(snapshot: snapshot(code: 63, day: true, place: "London"), unit: .celsius).frame(width: 224, height: 132)
    }
    .padding(20)
    let bitmap = try await render(cards, size: CGSize(width: 3 * 224 + 2 * 14 + 40, height: 172), name: "weather")
    #expect(nonBlackPixels(bitmap) > 10_000)
    let more = HStack(spacing: 14) {
      WeatherCard(snapshot: snapshot(code: 95, day: false, place: "Miami"), unit: .fahrenheit).frame(width: 224, height: 132)
      WeatherCard(snapshot: snapshot(code: 73, day: true, place: "Oslo"), unit: .celsius).frame(width: 224, height: 132)
      WeatherCard(snapshot: snapshot(code: 45, day: true, place: "Lisbon"), unit: .celsius).frame(width: 224, height: 132)
    }.padding(20)
    _ = try await render(more, size: CGSize(width: 3 * 224 + 2 * 14 + 40, height: 172), name: "weather-2")
  }

  @Test func statsCards() async throws {
    var input = StatsCardReading.Input()
    input.cpu = 0.42; input.memoryUsed = 11_400_000_000; input.memoryTotal = 18_000_000_000
    input.gpu = 0.18; input.diskFree = 214_000_000_000; input.diskTotal = 500_000_000_000
    input.networkDown = 1_250_000; input.networkUp = 86_000; input.batteryPercent = 64
    input.batteryCharging = true; input.thermal = .fair
    let rows = VStack(alignment: .leading, spacing: 10) {
      ForEach([[StatsCard.cpu, .ram], [.gpu, .disk], [.network, .battery], [.thermal, .cpu]], id: \.first) { pair in
        HStack(spacing: 8) { ForEach(pair) { StatsCardView(reading: .make($0, input)) } }.frame(width: 200)
      }
    }.padding(20)
    let bitmap = try await render(rows, size: CGSize(width: 240, height: 4 * 118 + 60), name: "stats")
    #expect(nonBlackPixels(bitmap) > 5_000)
  }

  @Test func glances() async throws {
    let model = IslandGlanceModel(settings: AppSettings(defaults: UserDefaults(suiteName: "glance-render")!), battery: (64, false))
    let strip = VStack(alignment: .leading, spacing: 10) {
      ForEach([IslandGlance.clock, .battery, .timer, .weather, .cpu], id: \.self) { glance in
        HStack(spacing: 70) {
          IslandGlanceContent(glance: glance, model: model, unit: .celsius, weather: snapshot(code: 2, day: true))
          Capsule().fill(.black).frame(width: 90, height: 30)
          Text(glance.title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).frame(height: 36).background(Color(white: 0.12), in: Capsule())
      }
    }.padding(20)
    let bitmap = try await render(strip, size: CGSize(width: 380, height: 5 * 46 + 30), name: "glances")
    #expect(nonBlackPixels(bitmap) > 1_000)
  }

  @Test func shelfWithMoreThanThreeWidgets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Brim-WidgetsTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    for (name, editing) in [("shelf", false), ("shelf-editing", true)] {
      let layout = HomeWidgetStore(
        widgets: [.weather, .stats, .timer, .clock, .batteries, .awake], persist: { _ in }, scrollMode: { .automatic })
      layout.isEditing = editing
      let shelf = IslandWidgetShelf(
        layout: layout, center: ActivityCenter(), store: ShelfStore(directory: directory),
        nowPlaying: NowPlayingModel(enabledSources: []), openTool: { _ in }, showShelf: {})
      let width = layout.shelfWidth
      let height = layout.shelfHeight
      let framed = shelf.padding(.horizontal, HomeWidgetStore.horizontalPadding / 2).padding(.top, 10)
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
      let bitmap = try await render(framed, size: CGSize(width: width, height: height), name: name)
      #expect(nonBlackPixels(bitmap) > 3_000)
    }
  }

  private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try? png.write(to: folder.appendingPathComponent("widgets-\(name).png"))
    }
    return bitmap
  }

  private func nonBlackPixels(_ bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.redComponent + c.greenComponent + c.blueComponent > 0.15 {
          count += 1
        }
      }
    }
    return count
  }
}
