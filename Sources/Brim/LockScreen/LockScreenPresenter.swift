import AppKit
import Combine
import os
import SwiftUI

/// A borderless panel that can sit above the login window. It never takes focus from the lock UI.
final class LockScreenPanel: NSPanel {
    static let desiredLevel = NSWindow.Level(rawValue: Int(Int32.max - 2))

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.desiredLevel
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panels never become key (the password field keeps focus), so the first click must reach the
/// SwiftUI buttons instead of being spent on activating the window.
final class LockScreenHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the two lock-screen windows (cards and status row), keeps them delegated to the SkyLight
/// space, and re-delegates them when the window server drops or demotes them.
@MainActor
final class LockScreenPresenter {
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "lockscreen")
    private static let watchdogInterval: TimeInterval = 2

    let viewModel: LockScreenViewModel
    private let bridge: LockScreenWindowBridge
    private var cardsPanel: LockScreenPanel?
    private var statusPanel: LockScreenPanel?
    private var lyricsPanel: LockScreenPanel?
    private var artworkPanel: LockScreenPanel?
    private var defaultsObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private var generation = 0
    private(set) var isPresented = false
    private(set) var redelegations = 0

    init(bridge: LockScreenWindowBridge, viewModel: LockScreenViewModel? = nil) {
        self.bridge = bridge
        self.viewModel = viewModel ?? LockScreenViewModel()
    }

    @discardableResult
    func present() -> Bool {
        guard bridge.isAvailable else { return false }
        generation += 1
        viewModel.refresh()
        isPresented = true
        relayout()
        Self.log.notice("lock-screen cards presented (media: \(self.viewModel.content.media != nil), screen: \(self.targetScreen?.localizedName ?? "none", privacy: .public))")
        // Live-update the visible lock UI when a lock-screen setting changes.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                self.viewModel.settingsDidChange()
                self.relayout()
            }
        }
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        return true
    }

    func dismiss(animated: Bool) {
        guard isPresented else { return }
        isPresented = false
        watchdog?.invalidate()
        watchdog = nil
        defaultsObserver.map(NotificationCenter.default.removeObserver)
        defaultsObserver = nil
        viewModel.artworkSceneOpen = false
        EdgeSliderController.shared.hide()
        generation += 1
        let token = generation
        let panels = [cardsPanel, statusPanel, lyricsPanel, artworkPanel].compactMap { $0 }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panels.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panels.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard self?.generation == token else { return }
                panels.forEach { $0.orderOut(nil) }
            }
        })
    }

    /// Runs every `watchdogInterval` seconds while presented: refreshes data and repairs the windows.
    func tick() {
        guard isPresented else { return }
        viewModel.refresh()
        relayout()
        repairIfNeeded()
    }

    // MARK: Layout

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func relayout() {
        guard let screen = targetScreen else { return }
        let layout = LockScreenLayout.plan(viewModel.inputs, screen: screen.frame)
        let kinds = layout.cards.map(\.kind)
        let scene = viewModel.artworkSceneOpen && viewModel.content.media != nil
        update(&cardsPanel, frame: scene ? nil : layout.cardsFrame, panelRoot: AnyView(
            LockCardsHost(model: viewModel, kinds: kinds)))
        update(&statusPanel, frame: scene ? nil : layout.statusRow, panelRoot: AnyView(StatusRowHost(model: viewModel)))
        let lyricsFrame = !scene && viewModel.showsLyrics
            ? LockLyricsLayout.frame(cardsFrame: layout.cardsFrame, statusRow: layout.statusRow, screen: screen.frame) : nil
        update(&lyricsPanel, frame: lyricsFrame, panelRoot: AnyView(LyricsHost(model: viewModel)))
        update(&artworkPanel, frame: scene ? screen.frame : nil, bleed: 0, panelRoot: AnyView(ArtworkSceneHost(model: viewModel)))
    }

    /// Room around a panel's content for its cards' soft shadows; a window cut to the content's
    /// exact size clips them into a hard-edged dark box.
    static let shadowBleed: CGFloat = 40

    private func update(_ panel: inout LockScreenPanel?, frame content: CGRect?, bleed: CGFloat = shadowBleed,
                        panelRoot root: AnyView) {
        guard let content else {
            panel?.orderOut(nil)
            return
        }
        let frame = content.insetBy(dx: -bleed, dy: -bleed)
        let panelRoot = bleed > 0 ? AnyView(root.padding(bleed)) : root
        if panel == nil {
            let created = LockScreenPanel(frame: frame)
            created.contentView = LockScreenHostingView(rootView: panelRoot)
            panel = created
        } else if let host = panel?.contentView as? NSHostingView<AnyView> {
            host.rootView = panelRoot
        }
        guard let panel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.alphaValue = 1
        // Ordering front and re-delegating every tick churns the window server; do it only when the
        // panel is not up yet. The watchdog repairs a panel that drops out of the space.
        guard !panel.isVisible || bridge.isDelegated(panel) != true else { return }
        orderInAndDelegate(panel)
    }

    /// Order front first, then move into the space: ordering front after delegating can hand the
    /// window back to the desktop space.
    private func orderInAndDelegate(_ panel: LockScreenPanel) {
        panel.orderFrontRegardless()
        if !delegate(panel) { Self.log.error("could not delegate a lock-screen window") }
    }

    /// After display wake or a screen change: re-show the space, re-place and re-delegate every panel.
    func resync() {
        guard isPresented else { return }
        bridge.reassert()
        viewModel.refresh()
        relayout()
        for panel in [cardsPanel, statusPanel, lyricsPanel, artworkPanel].compactMap({ $0 }) where panel.isVisible {
            orderInAndDelegate(panel)
        }
        Self.log.notice("lock-screen windows resynced (media: \(self.viewModel.content.media != nil))")
    }

    // MARK: Watchdog

    private func delegate(_ panel: LockScreenPanel) -> Bool {
        panel.level = LockScreenPanel.desiredLevel
        return bridge.delegate(panel)
    }

    private func repairIfNeeded() {
        for panel in [cardsPanel, statusPanel, lyricsPanel, artworkPanel].compactMap({ $0 }) where panel.isVisible {
            let drifted = panel.level != LockScreenPanel.desiredLevel
            let lost = bridge.isDelegated(panel) == false
            guard drifted || lost else { continue }
            redelegations += 1
            Self.log.notice("re-delegating lock-screen window (level drift: \(drifted), lost space: \(lost))")
            orderInAndDelegate(panel)
        }
    }

    func teardown() {
        dismiss(animated: false)
        [cardsPanel, statusPanel, lyricsPanel, artworkPanel].forEach { $0?.close() }
        cardsPanel = nil
        statusPanel = nil
        lyricsPanel = nil
        artworkPanel = nil
        bridge.teardown()
    }
}

private struct LockCardsHost: View {
    @ObservedObject var model: LockScreenViewModel
    let kinds: [LockCardKind]
    var body: some View {
        LockCardsStack(content: model.content, kinds: kinds, look: model.look, actions: model.actions)
    }
}

private struct StatusRowHost: View {
    @ObservedObject var model: LockScreenViewModel
    var body: some View { LockStatusRowView(items: model.statusItems, look: model.look) }
}

private struct LyricsHost: View {
    @ObservedObject var model: LockScreenViewModel
    var body: some View {
        if let media = model.content.media {
            LockScreenLyricsView(model: .shared, track: media.track)
        }
    }
}

private struct ArtworkSceneHost: View {
    @ObservedObject var model: LockScreenViewModel
    var body: some View {
        if let media = model.content.media {
            LockScreenArtworkScene(info: media, actions: model.actions, close: { model.artworkSceneOpen = false })
        }
    }
}
