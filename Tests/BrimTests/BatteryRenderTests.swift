import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct BatteryRenderTests {
  /// The tools page wraps each tool in a ScrollView, which clips anything drawn outside the frame.
  @Test func fullRingIsNotClippedByTheToolsScrollView() async throws {
    let original = BatteryPowerState.isLowPower
    BatteryPowerState.isLowPower = { false }
    defer { BatteryPowerState.isLowPower = original }
    let mac = DeviceBattery(id: "mac", name: "Mac", symbol: "macbook", percent: 100, charging: false,
                            accessoryName: "MacBook Pro", model: .mac, onPower: true)
    let page = ScrollView {
      BatteryActivityView(model: DeviceBatteryModel(devices: [mac])).frame(maxWidth: .infinity, alignment: .leading)
    }
    let bitmap = try await render(page, size: CGSize(width: 480, height: 170))
    let ring = try #require(greenBounds(bitmap))
    #expect(abs(ring.width - ring.height) <= 3, "A clipped ring is narrower than it is tall: \(ring)")
  }

  private func render<V: View>(_ view: V, size: CGSize) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1200))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  /// Bounding box, in pixels, of the ring's saturated green.
  private func greenBounds(_ bitmap: NSBitmapImageRep) -> CGRect? {
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          color.greenComponent > 0.6, color.redComponent < 0.5, color.blueComponent < 0.5
        else { continue }
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }
}
