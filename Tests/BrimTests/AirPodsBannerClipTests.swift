import AVFoundation
import AppKit
import SwiftUI
import Testing

@testable import Brim

@Suite("AirPods system banner clips")
struct AirPodsBannerClipTests {
  private let root = URL(fileURLWithPath: "/fake/Resources")

  private func clips(_ files: [String]) -> AirPodsBannerClip {
    let paths = Set(files.map { root.appendingPathComponent($0).path })
    return AirPodsBannerClip(root: root, fileExists: { paths.contains($0) })
  }

  @Test func colourThenDefaultThenPlainLoop() {
    let all = clips(["Banner-PID-8202-mov/Banner-PID-8202-3-Loop.mov", "Banner-PID-8202-mov/Banner-PID-8202-default-Loop.mov",
                     "Banner-PID-8202-mov/Banner-PID-8202-Loop.mov"])
    #expect(all.url(productID: 0x200A, kind: .max, colour: 3)?.lastPathComponent == "Banner-PID-8202-3-Loop.mov")
    #expect(all.url(productID: 0x200A, kind: .max, colour: 9)?.lastPathComponent == "Banner-PID-8202-default-Loop.mov")
    #expect(all.url(productID: 0x200A, kind: .max)?.lastPathComponent == "Banner-PID-8202-default-Loop.mov")
    let plain = clips(["Banner-PID-8202-mov/Banner-PID-8202-Loop.mov"])
    #expect(plain.url(productID: 0x200A, kind: .max, colour: 3)?.lastPathComponent == "Banner-PID-8202-Loop.mov")
  }

  @Test func missingFilesFallThroughToNil() {
    #expect(clips([]).url(productID: 0x2014, kind: .pro) == nil)
    #expect(clips(["Banner-PID-8212-mov/Banner-PID-8212-Loop.mov"]).url(productID: nil, kind: nil) == nil)
  }

  @Test func ownProductIDThenLookAlikeThenModel() {
    let files = ["Banner-PID-8212-mov/Banner-PID-8212-Loop.mov", "Banner-PID-8206-mov/Banner-PID-8206-Loop.mov",
                 "Banner-PID-8231-mov/Banner-PID-8231-Loop.mov"]
    let set = clips(files)
    // AirPods Pro 2 USB-C (0x2024 = 8228) has no banner of its own: it borrows Pro 2's.
    #expect(set.url(productID: 0x2024, kind: .pro)?.lastPathComponent == "Banner-PID-8212-Loop.mov")
    // A first-generation Pro uses its own.
    #expect(set.url(productID: 0x200E, kind: .pro)?.lastPathComponent == "Banner-PID-8206-Loop.mov")
    // Pro 3 (0x2027 = 8231) has its own banner.
    #expect(set.url(productID: 0x2027, kind: .pro)?.lastPathComponent == "Banner-PID-8231-Loop.mov")
    // Unknown product ID: the model's usual banner.
    #expect(set.url(productID: 0x9999, kind: .pro)?.lastPathComponent == "Banner-PID-8212-Loop.mov")
  }

  @Test func productIDMapping() {
    #expect(AirPodsBannerClip.productIDs(productID: nil, kind: .gen3) == [8211])
    #expect(AirPodsBannerClip.productIDs(productID: nil, kind: .gen4) == [8217])
    #expect(AirPodsBannerClip.productIDs(productID: nil, kind: .max) == [8202])
    #expect(AirPodsBannerClip.productIDs(productID: nil, kind: .original) == [8207, 8194])
    #expect(AirPodsBannerClip.productIDs(productID: 0x2014, kind: .pro) == [8212, 8206])
    #expect(AirPodsBannerClip.productIDs(productID: 0x201B, kind: .gen4) == [0x201B, 8217])
    #expect(AirPodsBannerClip.productIDs(productID: nil, kind: nil).isEmpty)
  }

  @Test func caseClipLookup() {
    let set = clips(["Banner-PID-8212-Case-mov/Banner-PID-8212-Case-Loop.mov"])
    #expect(set.caseClip(productID: 8212)?.lastPathComponent == "Banner-PID-8212-Case-Loop.mov")
    #expect(set.caseClip(productID: 8202) == nil)
  }

  @Test func productIDReachesTheCard() {
    let battery = DeviceBattery(id: "l", name: "n", symbol: "airpodspro", percent: 80, charging: nil,
                                accessoryID: "bluetooth:1", accessoryName: "AirPods Pro", part: .left,
                                model: .airPodsPro, productID: 0x2024)
    #expect(AirPodsBatteries.from([battery], accessoryID: "bluetooth:1")?.productID == 0x2024)
  }

  @Test func probeReadsTheProductID() throws {
    let json = #"{"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_address":"AA","device_productID":"0x2024","device_vendorID":"0x004C","device_batteryLevelLeft":"90%"}}]}]}"#
    let batteries = BluetoothBatteryProbe.decode(Data(json.utf8))
    #expect(batteries.first?.productID == 0x2024)
  }

  /// A stopped view holds no player (no decoder alive); starting builds one, stopping releases it.
  @MainActor @Test func playerViewStopsCompletely() throws {
    let url = try #require(AirPodsBannerClip().url(productID: nil, kind: .pro) ?? AirPodsBannerClip().url(productID: nil, kind: .gen4))
    let view = AirPodsBannerPlayerView(url: url)
    #expect(view.player == nil)
    view.start()
    #expect(view.player?.isMuted == true)
    #expect(view.playerLayer?.player != nil)
    view.stop()
    #expect(view.player == nil && view.playerLayer?.player == nil && view.showsPoster)
    #expect(!view.acceptsFirstResponder)
  }

  /// Uses the real system clip when this Mac has it: transparent corners, opaque earbuds.
  @MainActor @Test func realSystemClipHasAlpha() throws {
    guard let url = AirPodsBannerClip().url(productID: 0x2014, kind: .pro) else { return }
    for time in [0.0, 1.5, 3.0] {
      let image = try #require(AirPodsBannerStills.frame(url, at: time))
      let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
      #expect(cg.width == 168 && cg.height == 168)
      let rep = NSBitmapImageRep(cgImage: cg)
      for (x, y) in [(0, 0), (167, 0), (0, 167), (167, 167)] {
        #expect((rep.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.02, "corner \(x),\(y) at \(time)s")
      }
      var opaque = 0
      for y in 40..<130 { for x in 20..<150 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.98 { opaque += 1 } }
      #expect(opaque > 2000, "earbuds should be solid at \(time)s, got \(opaque) px")
    }
  }

  /// Live playback in a window: the clip plays, and it stops when the card goes inactive.
  @MainActor @Test func liveBannerPlaysAndStops() async throws {
    guard let url = AirPodsBannerClip().url(productID: 0x2014, kind: .pro) else { return }
    let view = AirPodsBannerPlayerView(url: url, poster: AirPodsBannerStills.frame(url))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 84, height: 84), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderFrontRegardless()
    defer { window.close() }
    view.start()
    try await Task.sleep(for: .milliseconds(700))
    #expect(view.isPlaying)
    let seconds = view.player?.currentTime().seconds ?? 0
    #expect(seconds > 0.1, "playback should advance, at \(seconds)s")
    #expect(view.playerLayer?.isReadyForDisplay == true)
    view.stop()
    #expect(!view.isPlaying && view.player == nil)
  }
}
