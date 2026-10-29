import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Real mouse events dragging one Home widget over another in edit mode must reorder them
/// (the user's case: the player and Weather, both medium, would not swap).
@MainActor
@Suite(.serialized)
struct HomeDragDeliveryTests {
  @Test func draggingThePlayerOntoWeatherSwapsThem() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("home-drag-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let layout = HomeWidgetStore(items: [HomeWidgetItem(.media, .medium), HomeWidgetItem(.weather, .medium)],
                                 persist: { _ in })
    layout.isEditing = true
    let size = CGSize(width: layout.shelfWidth, height: layout.shelfHeight)
    let shelf = IslandWidgetShelf(
      layout: layout, center: ActivityCenter(), store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(enabledSources: []), openTool: { _ in }, showShelf: {}
    )
    .padding(.horizontal, HomeWidgetStore.horizontalPadding / 2).padding(.top, HomeWidgetStore.topPadding)
    .frame(width: size.width, height: size.height, alignment: .top)
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: shelf)
    window.orderFrontRegardless()
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(400))

    // Window coordinates have their origin bottom-left; the grid row starts below the top padding.
    let rowY = size.height - HomeWidgetStore.topPadding - HomeWidgetStore.editMargin - HomeWidgetGrid.unit / 2
    let left = HomeWidgetStore.horizontalPadding / 2 + HomeWidgetStore.editMargin
    let from = CGPoint(x: left + HomeWidgetSize.medium.width / 2, y: rowY)
    let to = CGPoint(x: left + HomeWidgetSize.medium.width + HomeWidgetGrid.gap + HomeWidgetSize.medium.width * 0.75, y: rowY)
    func send(_ type: NSEvent.EventType, _ point: CGPoint) {
      window.sendEvent(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    }
    send(.leftMouseDown, from)
    for step in 1...12 {
      let t = CGFloat(step) / 12
      send(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: rowY))
      try await Task.sleep(for: .milliseconds(30))
    }
    send(.leftMouseUp, to)
    try await Task.sleep(for: .milliseconds(300))
    #expect(layout.widgets == [.weather, .media])
  }
}
