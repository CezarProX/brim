import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
struct PassiveStatusHomeTests {
    @Test func compactOnlyStatusesDoNotClaimAnEmptyExpandedPage() {
        for activity in [IslandActivity.privacy, .dnd, .hotspot] {
            #expect(NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: activity))
        }
    }

    @Test func realActivityCardsKeepTheirExistingPriority() {
        for activity in [IslandActivity.call, .recording, .timer, .agent, .download] {
            #expect(!NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: activity))
        }
        #expect(NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: .music))
        #expect(IslandActivities(recording: false, call: true, music: false, additional: [.privacy]).primary == .call)
        #expect(IslandActivities(recording: true, call: false, music: false, additional: [.privacy]).primary == .recording)
        #expect(IslandActivities(recording: false, call: false, music: true, additional: [.privacy]).primary == .music)
    }

    @Test func selectingAQuietIndicatorFallsBackToHomeInsteadOfEmptyView() throws {
        try withView { view, presentation, widgets in
            for activity in [IslandActivity.privacy, .dnd, .hotspot] {
                presentation.selectedActivity = activity
                #expect(view.isShelfHome)
                #expect(view.utilityContentHeight == widgets.shelfHeight)
            }
        }
    }

    @Test func microphoneCameraAndCombinedIndicatorsRemainVisibleWhileHomeHasContent() throws {
        let signals = SystemSignalsMonitor.shared
        let previous = (signals.cameraInUse, signals.microphoneInUse)
        defer { signals.preview(camera: previous.0, microphone: previous.1) }
        for state in [(false, true), (true, false), (true, true)] {
            signals.preview(camera: state.0, microphone: state.1)
            try withView { view, _, widgets in
                #expect(view.activities.primary == .privacy)
                #expect(view.layoutGeometry.route == .activity(.privacy))
                #expect(view.isShelfHome)
                #expect(view.utilityContentHeight == widgets.shelfHeight)
                #expect(view.preferredWidth == widgets.shelfWidth + 2 * view.shoulderInset)
            }
        }
    }

    @Test func micHoverRendersPopulatedHome() async throws {
        let signals = SystemSignalsMonitor.shared
        let previous = (signals.cameraInUse, signals.microphoneInUse)
        signals.preview(camera: false, microphone: true)
        defer { signals.preview(camera: previous.0, microphone: previous.1) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let center = ActivityCenter(calendar: CalendarActivityModel(), downloads: DownloadProgressModel(folder: { nil }))
        let store = ShelfStore(directory: directory)
        let widgets = HomeWidgetStore(widgets: [.clock, .captures], persist: { _ in })
        let geometry = NotchGeometry.dynamicIsland(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        func shell(expanded: Bool) -> some View {
            let presentation = NotchPresentation()
            presentation.geometry = geometry
            presentation.isExpanded = expanded
            return NotchShelfView(presentation: presentation, store: store,
                nowPlaying: NowPlayingModel(enabledSources: [], stream: nil),
                calls: CallActivityModel(accessibilityTrusted: { false }),
                recording: ScreenRecordingModel(probe: { nil }), timers: NativeTimerModel(probe: { nil }),
                extensions: center, homeWidgets: widgets, theme: IslandTheme(surface: .black),
                playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
                .frame(width: 600, height: expanded ? 250 : 70, alignment: .top)
        }
        let size = CGSize(width: 624, height: 360)
        let root = VStack(spacing: 16) {
            shell(expanded: false)
            shell(expanded: true)
        }.padding(12).frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(white: 0.18)).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".context/mic-hover-fixed.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        var bright = 0
        for y in stride(from: Int(100 * scale), to: bitmap.pixelsHigh - 10, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > 0.7, color.greenComponent > 0.7, color.blueComponent > 0.7 { bright += 1 }
            }
        }
        #expect(bright > 200, "Mic hover must show the clock/capture content, not an empty black activity")
    }

    private func withView(_ body: (NotchShelfView, NotchPresentation, HomeWidgetStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let presentation = NotchPresentation()
        let widgets = HomeWidgetStore(widgets: [.clock, .captures], persist: { _ in })
        let view = NotchShelfView(presentation: presentation, store: ShelfStore(directory: directory),
            nowPlaying: NowPlayingModel(enabledSources: [], stream: nil),
            calls: CallActivityModel(accessibilityTrusted: { false }),
            recording: ScreenRecordingModel(probe: { nil }), timers: NativeTimerModel(probe: { nil }),
            extensions: ActivityCenter(calendar: CalendarActivityModel(), downloads: DownloadProgressModel(folder: { nil })),
            homeWidgets: widgets)
        try body(view, presentation, widgets)
    }
}
