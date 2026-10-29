import AppKit
import AVFoundation
import CoreAudio
import SwiftUI
import Testing

@testable import Brim

@MainActor
private final class RefusingEngine: AppVolumeApplying {
  var activeAppIDs: Set<String> { [] }
  func apply(appID: String, processes: [UInt32], gain: Float, outputUID: String?) throws {
    throw AppVolumeTapError.system("tap the app", kAudioHardwareIllegalOperationError)
  }
  func release(appID: String) {}
  func releaseAll() {}
  func defaultOutputChanged() {}
}

private struct TwoApps: AudioProcessListing {
  func processes() -> [AudioProcessInfo] {
    [AudioProcessInfo(objectID: 1, pid: 10, bundleID: "com.spotify.client", isRunningOutput: true, isRunningInput: false),
     AudioProcessInfo(objectID: 2, pid: 11, bundleID: "com.apple.Safari", isRunningOutput: true, isRunningInput: false)]
  }
}

private struct Rooms: AudioDeviceListing {
  var airplay: Bool
  func devices() -> [AudioDeviceRef] {
    var list = [AudioDeviceRef(id: 1, uid: "spk", name: "MacBook Pro Speakers", isOutput: true, isInput: false, isAirPlay: false, isBluetooth: false, isAggregate: false),
                AudioDeviceRef(id: 2, uid: "pods", name: "Alex's AirPods Pro", isOutput: true, isInput: true, isAirPlay: false, isBluetooth: true, isAggregate: false)]
    if airplay { list.append(AudioDeviceRef(id: 3, uid: "tv", name: "Living Room", isOutput: true, isInput: false, isAirPlay: true, isBluetooth: false, isAggregate: false)) }
    return list
  }
  func defaultDevice(input: Bool) -> AudioDeviceRef? { input ? nil : devices().last }
  func setDefault(_ device: AudioDeviceRef, input: Bool) -> Bool { device.uid != "pods" }
}

@MainActor
@Suite(.serialized)
struct AppsMediaRenderTests {
  private func render<V: View>(_ content: V, name: String, height: CGFloat) async throws -> NSBitmapImageRep {
    let size = CGSize(width: 620, height: height)
    let host = NSHostingView(rootView: content.padding(.horizontal, 28).frame(width: size.width, height: size.height, alignment: .top)
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
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("apps-\(name).png"))
    return bitmap
  }

  private func settings() -> AppSettings { AppSettings(defaults: UserDefaults(suiteName: "apps-media-\(UUID().uuidString)")!) }
  private let height = IslandWidgetTile.audioControl.openHeight - 70

  // MARK: Audio Control

  @Test func audioFirstRunShowsHint() async throws {
    let model = AudioControlModel(lister: TwoApps(), directory: Rooms(airplay: false), engine: RefusingEngine(), settings: settings(), appName: { $0 })
    model.refresh()
    #expect(model.isUntouched)
    #expect(!model.needsPermission)
    _ = try await render(AudioControlView(model: model, showsTitle: false), name: "audio-first-run", height: height)
  }

  @Test func audioPermissionRefusalIsExplained() async throws {
    let model = AudioControlModel(lister: TwoApps(), directory: Rooms(airplay: false), engine: RefusingEngine(), settings: settings(), appName: { $0 })
    model.refresh()
    model.setSlider("com.spotify.client", 0.5)
    #expect(model.needsPermission)
    #expect(model.rows.first { $0.id == "com.spotify.client" }?.needsPermission == true)
    _ = try await render(AudioControlView(model: model, showsTitle: false), name: "audio-permission", height: height)
  }

  @Test func permissionErrorClassification() {
    #expect(AppVolumeTapError.system("x", kAudioHardwareIllegalOperationError).isPermission)
    #expect(!AppVolumeTapError.system("x", 5).isPermission)
    #expect(!AppVolumeTapError.noProcesses.isPermission)
  }

  // MARK: AirPlay Rooms

  @Test func airPlayRoomStates() async throws {
    let on = AirPlayRoomModel(directory: Rooms(airplay: true), readLevel: { 0.6 }, writeLevel: { _ in true })
    on.refresh()
    #expect(on.isAirPlay)
    _ = try await render(AirPlayRoomPanel(model: on), name: "airplay-connected", height: height)
    let off = AirPlayRoomModel(directory: Rooms(airplay: false), readLevel: { nil }, writeLevel: { _ in false })
    off.refresh()
    #expect(!off.hasAirPlayOutput)
    _ = try await render(AirPlayRoomPanel(model: off), name: "airplay-none", height: height)
  }

  @Test func airPlaySelectFailureIsReported() {
    let model = AirPlayRoomModel(directory: Rooms(airplay: true), readLevel: { 0.5 }, writeLevel: { _ in true })
    model.refresh()
    model.select(model.outputs.first { $0.uid == "pods" }!)
    #expect(model.switchFailed)
    model.select(model.outputs.first { $0.uid == "spk" }!)
    #expect(!model.switchFailed)
  }

  @Test func airPlaySliderWritesAndClamps() {
    var written: Float?
    let model = AirPlayRoomModel(directory: Rooms(airplay: true), readLevel: { 0.5 }, writeLevel: { written = $0; return true })
    model.refresh()
    model.setLevel(1.7)
    #expect(written == 1)
    #expect(model.level == 1)
  }

  // MARK: Camera

  @Test func cameraStates() async throws {
    let denied = CameraSource(authorization: { .denied }, requestAccess: { false }, cameras: { [] })
    let model = CameraMirrorModel(source: denied, defaults: UserDefaults(suiteName: "cam-\(UUID().uuidString)")!)
    await model.appear()
    #expect(model.state == .denied)
    model.disappear()

    let fresh = CameraSource(authorization: { .notDetermined }, requestAccess: { false }, cameras: { [] })
    let first = CameraMirrorModel(source: fresh, defaults: UserDefaults(suiteName: "cam-\(UUID().uuidString)")!)
    await first.appear()
    #expect(first.state == .needsAccess)
    await first.allowAccess()
    #expect(first.state == .denied)
    first.disappear()

    let none = CameraSource(authorization: { .authorized }, requestAccess: { true }, cameras: { [] })
    let empty = CameraMirrorModel(source: none, defaults: UserDefaults(suiteName: "cam-\(UUID().uuidString)")!)
    await empty.appear()
    #expect(empty.state == .noCamera)
    empty.disappear()

    for (state, name) in [(CameraMirrorState.needsAccess, "needs-access"), (.denied, "denied"), (.noCamera, "no-camera"), (.busy, "busy"), (.starting, "starting")] {
      let preview = CameraMirrorModel(source: none, defaults: UserDefaults(suiteName: "cam-\(UUID().uuidString)")!)
      preview.loadPreview(state: state)
      _ = try await render(CameraMirrorView(model: preview), name: "camera-\(name)", height: IslandWidgetTile.camera.openHeight - 70)
    }
  }

  // MARK: Share

  private func tempFiles(_ names: [String]) throws -> [URL] {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try names.map { name in
      let url = dir.appendingPathComponent(name)
      try Data("x".utf8).write(to: url)
      return url
    }
  }

  @Test func shareAcceptsFilesFoldersAndSkipsMissing() throws {
    let model = SharingActivityModel()
    let files = try tempFiles(["a.txt", "b.png"])
    let folder = files[0].deletingLastPathComponent()
    model.accept(files + [folder, URL(fileURLWithPath: "/nonexistent/zzz")])
    #expect(model.files.count == 3)
    #expect(model.notice != nil)
    model.remove(files[0])
    #expect(model.files.count == 2)
    model.accept(files)
    #expect(model.notice == nil)
    model.clear()
    #expect(model.files.isEmpty)
  }

  @Test func shareLimitsToTen() throws {
    let model = SharingActivityModel()
    model.accept(try tempFiles((0..<14).map { "f\($0).txt" }))
    #expect(model.files.count == 10)
  }

  @Test func shareStatesRender() async throws {
    let empty = SharingActivityModel()
    _ = try await render(SharingActivityView(model: empty), name: "share-empty", height: IslandWidgetTile.share.openHeight - 70)
    let full = SharingActivityModel()
    full.accept(try tempFiles(["Invoice.pdf", "Holiday.png", "Notes.md", "Demo.mov"]))
    full.link = "https://example.com/brim"
    _ = try await render(SharingActivityView(model: full), name: "share-files", height: IslandWidgetTile.share.openHeight - 70)
  }
}
