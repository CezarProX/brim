import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Films the floating pill (notchless display) closing, frame by frame, by capturing this process's
/// own window, so no Screen Recording permission is needed. Off unless `QS_PILL_FILM` is set to an
/// output directory; it writes PNGs and asserts nothing.
@MainActor
@Suite(.serialized)
struct IslandPillCloseFilmTests {
  private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

  @Test(.enabled(if: ProcessInfo.processInfo.environment["QS_PILL_FILM"] != nil))
  func filmPillClose() async throws {
    let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["QS_PILL_FILM"]))
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    // CGWindowListCreateImage is unavailable to Swift on the current SDK but still answers for our own windows.
    let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"))
    let capture = unsafeBitCast(symbol, to: WindowImage.self)
    let screen = try #require(NSScreen.screens.first { $0.safeAreaInsets.top == 0 } ?? NSScreen.screens.first)
    let style = IslandSurfaceStyle(rawValue: ProcessInfo.processInfo.environment["QS_PILL_STYLE"] ?? "") ?? .dynamicGlass
    let presentation = NotchPresentation()
    presentation.geometry = NotchGeometry.make(
      screenFrame: screen.frame, hardwareNotch: nil, style: .island, tuning: .current(.shared))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      theme: IslandTheme(surface: style, glassLevel: 0.785))
    let panel = NSPanel(
      contentRect: presentation.geometry.hostingFrame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar + 2
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let backdrop = NSPanel(
      contentRect: presentation.geometry.hostingFrame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    backdrop.isReleasedWhenClosed = false
    backdrop.backgroundColor = NSColor(white: 0.92, alpha: 1)
    backdrop.level = .statusBar + 1
    backdrop.collectionBehavior = panel.collectionBehavior
    backdrop.orderFrontRegardless()
    defer { backdrop.close() }
    panel.contentView = NSHostingView(rootView: view)
    panel.setFrame(presentation.geometry.hostingFrame, display: true)
    panel.orderFrontRegardless()
    defer { panel.close() }
    try await Task.sleep(for: .seconds(1.2))
    withAnimation(NotchMotion.expansion(true, reduceMotion: false)) { presentation.isExpanded = true }
    try await Task.sleep(for: .seconds(1.4))

    // Quartz coordinates: top-left origin on the primary display.
    let primaryHeight = NSScreen.screens[0].frame.height
    let frame = panel.frame
    let rect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    let ids = [UInt32(panel.windowNumber), UInt32(backdrop.windowNumber)]
    func grab(_ index: Int) {
      // onScreenAboveWindow of the backdrop, including it: the island composited over the light card.
      guard let image = capture(rect, 1 << 1 | 1 << 3, ids[1], 0)?.takeRetainedValue() else { return }
      let rep = NSBitmapImageRep(cgImage: image)
      let url = output.appendingPathComponent(String(format: "f%03d.png", index))
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    grab(0)
    withAnimation(NotchMotion.expansion(false, reduceMotion: false)) { presentation.isExpanded = false }
    let start = Date()
    var index = 1
    while Date().timeIntervalSince(start) < 0.9 {
      grab(index)
      index += 1
      try await Task.sleep(for: .milliseconds(12))
    }
  }
}
