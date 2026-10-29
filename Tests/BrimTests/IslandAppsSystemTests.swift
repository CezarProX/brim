import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Logic and renders for System Stats, Batteries, Keep Awake and Front App. PNGs: `.renders/apps-*.png`.
@MainActor
@Suite(.serialized)
struct IslandAppsSystemTests {
  // MARK: Logic

  @Test func keepAwakeHoldsARealAssertionAndReleasesIt() async throws {
    let model = KeepAwakeModel()
    model.start(minutes: 30, keepDisplayOn: false)
    #expect(model.isActive && model.sessionMinutes == 30 && !model.keepsDisplayOn)
    #expect(assertionsText().contains("Brim Keep Awake"))
    model.setKeepsDisplayOn(true)
    #expect(model.keepsDisplayOn)
    model.stop(announce: false)
    #expect(!model.isActive && model.until == nil && model.sessionMinutes == nil)
    #expect(!assertionsText().contains("Brim Keep Awake"))
  }

  @Test func keepAwakeRingFractionAndLabels() {
    let start = Date(timeIntervalSince1970: 1000)
    let until = start.addingTimeInterval(600)
    #expect(KeepAwakeAppView.remainingFraction(until: until, startedAt: start, now: start.addingTimeInterval(150)) == 0.75)
    #expect(KeepAwakeAppView.remainingFraction(until: nil, startedAt: start, now: start) == nil)
    #expect(KeepAwakeAppView.label(minutes: 120) == "2 h")
    #expect(KeepAwakeAppView.label(minutes: 15) == "15 min")
    #expect(KeepAwakeAppView.label(minutes: nil) == "Until off")
  }

  @Test func frontAppRecentsAndProtection() {
    #expect(FrontAppModel.promote(3, in: [1, 2, 3, 4]) == [3, 1, 2, 4])
    #expect(FrontAppModel.promote(9, in: []) == [9])
    #expect(FrontAppModel.isProtected(bundleID: "com.apple.finder"))
    #expect(!FrontAppModel.isProtected(bundleID: "com.apple.Safari"))
  }

  @Test func frontAppModelSeesRunningApps() {
    let model = FrontAppModel()
    model.attach()
    defer { model.detach() }
    #expect(model.front != nil, "a logged-in Mac always has a regular app running")
    #expect(!model.recents.isEmpty)
  }

  @Test func statsModelProducesRealReadings() async throws {
    let model = SystemStatsModel()
    model.attach()
    defer { model.detach() }
    try await Task.sleep(for: .milliseconds(900))
    #expect(model.hasCPUReading)
    #expect(model.memoryUsed > 0 && model.memoryUsed <= model.memoryTotal)
    #expect(model.diskTotal > 0 && model.diskFree > 0)
    #expect(StatsAppView.tint(.teal, level: 0.95) == .red)
  }

  private func assertionsText() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: Renders

  private func shot(_ tile: IslandWidgetTile, _ state: String, @ViewBuilder content: () -> some View) async throws {
    let size = CGSize(width: 556, height: 32 + tile.openHeight)
    let body = VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack(spacing: 10) {
        Image(systemName: "chevron.left").frame(width: 26, height: 26).background(IslandFill.raised, in: Circle())
        IslandWidgetIcon(tile: tile, size: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(tile.title).font(IslandFont.title)
          Text(tile.subtitle ?? "").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
        }
        Spacer()
      }.frame(height: 34)
      content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
    .frame(width: size.width, height: tile.openHeight, alignment: .top)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    .foregroundStyle(IslandInk.primary)
    let root = body.frame(width: size.width, height: size.height, alignment: .bottom)
      .background(Color(white: 0.25)).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1500))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("apps-\(state).png"))
  }

  @Test func renderStats() async throws {
    let model = SystemStatsModel()
    model.attach()
    defer { model.detach() }
    try await Task.sleep(for: .milliseconds(1500))
    try await shot(.stats, "stats-live") { StatsAppView(model: model) }
  }

  @Test func renderDevices() async throws {
    let mac = DeviceBattery(id: "mac", name: "Mac", symbol: "macbook", percent: 100, charging: false,
                            accessoryName: "MacBook Pro", model: .mac, onPower: true)
    let pods = ["Left": 66, "Right": 67, "Case": 51]
    let buds = [
      DeviceBattery(id: "b:l", name: "p · Left", symbol: AccessoryModel.other.glyph(for: .left), percent: pods["Left"]!,
                    charging: nil, accessoryID: "b", accessoryName: "Alex’s AirPods Pro", part: .left, model: .other),
      DeviceBattery(id: "b:r", name: "p · Right", symbol: AccessoryModel.other.glyph(for: .right), percent: pods["Right"]!,
                    charging: nil, accessoryID: "b", accessoryName: "Alex’s AirPods Pro", part: .right, model: .other),
      DeviceBattery(id: "b:c", name: "p · Case", symbol: AccessoryModel.other.glyph(for: .case), percent: pods["Case"]!,
                    charging: nil, accessoryID: "b", accessoryName: "Alex’s AirPods Pro", part: .case, model: .other),
    ]
    try await shot(.devices, "devices-list") { DevicesAppView(model: DeviceBatteryModel(devices: [mac] + buds)) }
    try await shot(.devices, "devices-empty") { DevicesAppView(model: DeviceBatteryModel(devices: [])) }
    try await shot(.devices, "devices-loading") { DevicesAppView(model: DeviceBatteryModel()) }
  }

  @Test func renderKeepAwake() async throws {
    let off = KeepAwakeModel()
    try await shot(.keepAwake, "keepawake-off") { KeepAwakeAppView(model: off) }
    let on = KeepAwakeModel()
    on.start(minutes: 60)
    defer { on.stop(announce: false) }
    try await shot(.keepAwake, "keepawake-on") { KeepAwakeAppView(model: on) }
  }

  @Test func renderFrontApp() async throws {
    let model = FrontAppModel()
    model.attach()
    defer { model.detach() }
    try await shot(.frontApp, "frontapp") { FrontAppView(model: model, workspace: WorkspaceActivityModel()) }
  }
}
