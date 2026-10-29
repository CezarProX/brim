import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Opens and closes a real island on screen (live AppKit glass, no wallpaper snapshot) so the
/// morph can be filmed and checked frame by frame. Off unless `QS_MORPH_FILM=1`; it only shows
/// windows and asserts nothing.
@MainActor
@Suite(.serialized)
struct IslandMorphFilmTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["QS_MORPH_FILM"] == "1"))
  func filmOpenAndClose() async throws {
    let screen = try #require(NSScreen.screens.first)
    let presentation = NotchPresentation()
    presentation.geometry = ShellEnvironment.geometry(for: screen)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      theme: IslandTheme(surface: .dynamicGlass, glassLevel: 0.785))
    let panel = NSPanel(
      contentRect: presentation.geometry.hostingFrame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar + 2
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    // A plain light card under the island, so the shell's outline reads whatever is on screen.
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
    try await Task.sleep(for: .seconds(1.5))
    let cycles = Int(ProcessInfo.processInfo.environment["QS_MORPH_CYCLES"] ?? "") ?? 2
    for _ in 0..<cycles {
      for expanded in [true, false] {
        withAnimation(NotchMotion.expansion(expanded, reduceMotion: false)) {
          presentation.isExpanded = expanded
        }
        try await Task.sleep(for: .seconds(1.6))
      }
    }
  }
}
