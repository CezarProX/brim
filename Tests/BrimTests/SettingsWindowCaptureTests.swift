import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Captures the real Settings window (title bar, Liquid Glass sidebar, vibrancy) with `screencapture`,
/// which an offscreen `cacheDisplay` cannot draw. The window is ordered in far off screen without
/// activating Brim, captured by window ID, then closed. PNGs land in `.renders/settings-window-*.png`.
/// When `screencapture` is unavailable (no Screen Recording permission) the test records nothing.
@MainActor
@Suite(.serialized)
struct SettingsWindowCaptureTests {
  @Test(arguments: SettingsPane.allCases)
  func capture(_ pane: SettingsPane) async throws {
    try await capture(SettingsDestination(pane), file: pane.renderName, appearance: nil)
  }

  /// Deep links: a tool page with its row highlighted, and a row inside a page's Advanced group.
  @Test(arguments: [
    (SettingsDestination.tool(.weather, anchor: "weather.enable"), "deeplink-weather"),
    (SettingsDestination(.island, anchor: "island.displays"), "deeplink-island-displays"),
    (SettingsDestination.tool(.stats), "tool-stats"),
    (SettingsDestination(.widgets, anchor: "tool.mcp"), "deeplink-widgets-mcp"),
  ])
  func captureDeepLink(_ destination: SettingsDestination, file: String) async throws {
    try await capture(destination, file: file, appearance: nil, wait: 1600)
  }

  /// The same window in the light appearance, to check contrast and materials there too.
  @Test(arguments: [(SettingsPane.general, "general-light"), (.widgets, "widgets-light")])
  func captureLight(_ pane: SettingsPane, file: String) async throws {
    try await capture(SettingsDestination(pane), file: file, appearance: NSAppearance(named: .aqua))
  }

  private func capture(
    _ destination: SettingsDestination, file: String, appearance: NSAppearance?, wait: Int = 900
  ) async throws {
    let window = SettingsWindowController.makeWindow(rootView: SettingsRootView(destination: destination))
    window.appearance = appearance
    defer { window.orderOut(nil); window.close() }
    window.orderFrontRegardless()
    // Off every screen, so nothing flashes on the user's display.
    window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
    try await Task.sleep(for: .milliseconds(wait))

    let url = rendersDirectory().appendingPathComponent("settings-window-\(file).png")
    try? FileManager.default.removeItem(at: url)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
      let image = try #require(NSImage(contentsOf: url))
      #expect(image.size.width > 400)
    }
  }

  private func rendersDirectory() -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
