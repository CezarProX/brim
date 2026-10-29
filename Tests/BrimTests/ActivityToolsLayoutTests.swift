import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
struct ActivityToolsLayoutTests {
  @Test("Tool grid stays inside the 424-point content area of the 480-point utility shell")
  func toolGridHasNoHorizontalOverflow() async throws {
    let canvasSize = CGSize(width: 480, height: 164)
    let contentWidth: CGFloat = 424
    let gutter = (canvasSize.width - contentWidth) / 2
    let view = ZStack {
      Color(.displayP3, red: 1, green: 0, blue: 0, opacity: 1)
      ActivityToolsView(center: ActivityCenter(), selection: .constant(nil))
        .frame(width: contentWidth, height: canvasSize.height, alignment: .topLeading)
        .background(.black)
    }
    .frame(width: canvasSize.width, height: canvasSize.height)

    let bitmap = try await render(view, size: canvasSize)
    let directory = URL(fileURLWithPath: "/tmp/brim-expansion-renders", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(
      to: directory.appendingPathComponent("activity-tools-overflow.png"))
    let scale = CGFloat(bitmap.pixelsWide) / canvasSize.width
    let gutterPixels = Int(gutter * scale)
    let sentinel = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
    let content = try #require(
      bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
    #expect(colorDistance(sentinel, content) > 0.5,
            "The overflow sentinel must remain visually distinct from the tool content")
    var sampled = 0
    var unchanged = 0

    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
      for x in stride(from: 0, to: gutterPixels, by: 2) {
        sampled += 2
        if matches(bitmap.colorAt(x: x, y: y), sentinel) { unchanged += 1 }
        if matches(bitmap.colorAt(x: bitmap.pixelsWide - 1 - x, y: y), sentinel) {
          unchanged += 1
        }
      }
    }

    #expect(unchanged > sampled * 99 / 100,
            "Tool cards and labels must not draw into either 28-point shell gutter")
  }

  private func render<V: View>(_ view: V, size: CGSize) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func matches(_ color: NSColor?, _ expected: NSColor) -> Bool {
    guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
    return colorDistance(color, expected) < 0.02
  }

  private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    abs(lhs.redComponent - rhs.redComponent) + abs(lhs.greenComponent - rhs.greenComponent)
      + abs(lhs.blueComponent - rhs.blueComponent) + abs(lhs.alphaComponent - rhs.alphaComponent)
  }
}
