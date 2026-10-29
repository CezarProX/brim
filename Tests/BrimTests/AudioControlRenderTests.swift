import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
private final class PreviewEngine: AppVolumeApplying {
  var activeAppIDs: Set<String> { [] }
  func apply(appID: String, processes: [UInt32], gain: Float, outputUID: String?) throws {}
  func release(appID: String) {}
  func releaseAll() {}
  func defaultOutputChanged() {}
}

private struct PreviewLister: AudioProcessListing {
  func processes() -> [AudioProcessInfo] {
    [("com.spotify.client", true), ("com.google.Chrome", true), ("com.apple.Safari", true), ("us.zoom.xos", true), ("com.hnc.Discord", true)]
      .enumerated().map { AudioProcessInfo(objectID: UInt32($0.offset + 1), pid: Int32($0.offset + 100), bundleID: $0.element.0, isRunningOutput: $0.element.1, isRunningInput: false) }
  }
}

private struct PreviewDirectory: AudioDeviceListing {
  func devices() -> [AudioDeviceRef] {
    [AudioDeviceRef(id: 1, uid: "spk", name: "MacBook Pro Speakers", isOutput: true, isInput: false, isAirPlay: false, isBluetooth: false, isAggregate: false),
     AudioDeviceRef(id: 2, uid: "pods", name: "Alex's AirPods Pro", isOutput: true, isInput: true, isAirPlay: false, isBluetooth: true, isAggregate: false),
     AudioDeviceRef(id: 3, uid: "tv", name: "Living Room", isOutput: true, isInput: false, isAirPlay: true, isBluetooth: false, isAggregate: false),
     AudioDeviceRef(id: 4, uid: "kitchen", name: "Kitchen HomePod", isOutput: true, isInput: false, isAirPlay: true, isBluetooth: false, isAggregate: false)]
  }
  func defaultDevice(input: Bool) -> AudioDeviceRef? { input ? nil : devices()[2] }
  func setDefault(_ device: AudioDeviceRef, input: Bool) -> Bool { true }
}

@MainActor
@Suite(.serialized)
struct AudioControlRenderTests {
  private func render<V: View>(_ content: V, name: String, size: CGSize) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
      .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(300))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
    return bitmap
  }

  private func bright(_ bitmap: NSBitmapImageRep, _ area: CGRect) -> Int {
    var count = 0
    for y in stride(from: Int(area.minY), to: min(bitmap.pixelsHigh, Int(area.maxY)), by: 2) {
      for x in stride(from: Int(area.minX), to: min(bitmap.pixelsWide, Int(area.maxX)), by: 2) {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent + c.greenComponent + c.blueComponent > 1.2 { count += 1 }
      }
    }
    return count
  }

  private func model() -> AudioControlModel {
    let defaults = UserDefaults(suiteName: "audio-render-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    settings.audioAllowBoost = true
    let names = ["com.spotify.client": "Spotify", "com.google.Chrome": "Google Chrome", "com.apple.Safari": "Safari",
                 "us.zoom.xos": "zoom.us", "com.hnc.Discord": "Discord"]
    let model = AudioControlModel(lister: PreviewLister(), directory: PreviewDirectory(), engine: PreviewEngine(),
                                  settings: settings, appName: { names[$0] ?? $0 })
    model.refresh()
    model.setSlider("com.spotify.client", 0.72)
    model.setSlider("com.google.Chrome", 1.4)
    model.toggleMute("com.apple.Safari")
    model.setOutput("us.zoom.xos", uid: "pods")
    model.setSlider("us.zoom.xos", 0.9)
    return model
  }

  @Test func audioControlPanelRenders() async throws {
    let bitmap = try await render(AudioControlView(model: model()), name: "audio-control", size: AudioControlView.preferredSize)
    #expect(bright(bitmap, CGRect(x: 0, y: 0, width: 1120, height: 400)) > 400, "rows must draw")
  }

  @Test func audioControlEmptyStateRenders() async throws {
    struct Empty: AudioProcessListing { func processes() -> [AudioProcessInfo] { [] } }
    let empty = AudioControlModel(lister: Empty(), directory: PreviewDirectory(), engine: PreviewEngine(),
                                  settings: AppSettings(defaults: UserDefaults(suiteName: "audio-empty-\(UUID().uuidString)")!))
    _ = try await render(AudioControlView(model: empty), name: "audio-control-empty", size: AudioControlView.preferredSize)
  }

  @Test func roomPickerRenders() async throws {
    let room = AirPlayRoomModel(directory: PreviewDirectory(), readLevel: { 0.62 }, writeLevel: { _ in true })
    room.refresh()
    let bitmap = try await render(AirPlayRoomPanel(model: room),
                                  name: "airplay-room", size: AirPlayRoomPanel.preferredSize)
    #expect(bright(bitmap, CGRect(x: 0, y: 0, width: 1120, height: 400)) > 300)
  }

  @Test func automixMorphRenders() async throws {
    let stages: [Double] = [0, 0.35, 0.7, 1]
    let strip = HStack(spacing: 28) {
      ForEach(stages, id: \.self) { value in
        VStack(spacing: 6) {
          AutomixMorph(progress: value, waveform: HStack(spacing: 2) {
            ForEach(0..<5) { i in Capsule().fill(.pink).frame(width: 3, height: CGFloat(6 + (i % 3) * 5)) }
          }, tint: .pink).scaleEffect(2.2).frame(width: 60, height: 50)
          Text("\(Int(value * 100))%").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
      }
      AudioQualityBadge(quality: .lossless)
      AudioQualityBadge(quality: .hiRes)
      AudioQualityBadge(quality: .atmos)
    }
    .padding(20)
    let bitmap = try await render(strip, name: "automix-morph", size: CGSize(width: 640, height: 110))
    #expect(bright(bitmap, CGRect(x: 0, y: 0, width: 1280, height: 220)) > 50)
  }

  private actor NoProvider: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
  }
}
