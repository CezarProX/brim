import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Deliver clicks through the real hosting view, including edit controls on the card's edges.
@MainActor
@Suite(.serialized)
struct HomeWidgetInteractionTests {
    @Test func removeBadgeRespondsAtItsVisibleCenterWhileWidgetsJiggle() async throws {
        try await withShelf { layout, window, size in
            let left = HomeWidgetStore.horizontalPadding / 2 + HomeWidgetStore.editMargin
            let top = size.height - HomeWidgetStore.topPadding - HomeWidgetStore.editMargin
            // The 28pt control is inset 2pt; press the visible circle's outer quadrant.
            click(window, CGPoint(x: left + 16 - 4, y: top - 16 + 4))
            try await Task.sleep(for: .milliseconds(250))
            #expect(layout.widgets == [.weather])
        }
    }

    @Test func resizeHandleRespondsAtItsVisibleCenterWhileWidgetsJiggle() async throws {
        try await withShelf { layout, window, size in
            let left = HomeWidgetStore.horizontalPadding / 2 + HomeWidgetStore.editMargin
            let top = size.height - HomeWidgetStore.topPadding - HomeWidgetStore.editMargin
            click(window, CGPoint(x: left + HomeWidgetSize.medium.width - 16 + 4,
                                  y: top - HomeWidgetStore.rowHeight + 16 - 4))
            try await Task.sleep(for: .milliseconds(250))
            #expect(layout.size(of: .media) == .small)
            #expect(layout.widgets == [.media, .weather])
        }
    }

    @Test func removeBadgeKeepsTheClickWhenThePointerMovesSlightly() async throws {
        try await withShelf { layout, window, size in
            let left = HomeWidgetStore.horizontalPadding / 2 + HomeWidgetStore.editMargin
            let top = size.height - HomeWidgetStore.topPadding - HomeWidgetStore.editMargin
            click(window, CGPoint(x: left + 16, y: top - 16), jitter: CGSize(width: 4, height: 0))
            try await Task.sleep(for: .milliseconds(250))
            #expect(layout.widgets == [.weather], "The body's 3pt reorder recognizer must not steal a badge click")
        }
    }

    private func click(_ window: NSWindow, _ point: CGPoint, jitter: CGSize = .zero) {
        let end = CGPoint(x: point.x + jitter.width, y: point.y + jitter.height)
        let events: [(NSEvent.EventType, CGPoint)] = jitter == .zero
            ? [(.leftMouseDown, point), (.leftMouseUp, end)]
            : [(.leftMouseDown, point), (.leftMouseDragged, end), (.leftMouseUp, end)]
        for (type, location) in events {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
    }

    private func withShelf(_ body: (HomeWidgetStore, NSWindow, CGSize) async throws -> Void) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("home-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = HomeWidgetStore(items: [HomeWidgetItem(.media, .medium), HomeWidgetItem(.weather, .medium)],
                                     persist: { _ in })
        layout.isEditing = true
        let size = CGSize(width: layout.shelfWidth, height: layout.shelfHeight)
        let player = await OnboardingSamples.nowPlaying()
        let shelf = IslandWidgetShelf(layout: layout, center: ActivityCenter(), store: ShelfStore(directory: directory),
            nowPlaying: player, openTool: { _ in }, showShelf: {})
            .padding(.horizontal, HomeWidgetStore.horizontalPadding / 2).padding(.top, HomeWidgetStore.topPadding)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: shelf)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent(".context/widgets-edit-1.0.3.png")
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output)
        try await body(layout, window, size)
    }
}
