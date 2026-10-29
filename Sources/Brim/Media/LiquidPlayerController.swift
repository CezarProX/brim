import AppKit
import Combine
import SwiftUI

/// Drives the floating Liquid Player window: pop-out from the notch, two-finger vertical morph
/// between sizes, click-to-cycle, desktop/over-apps level, and the optional menu-bar drop-down.
@MainActor
final class LiquidPlayerController: NSObject, ObservableObject {
    static let shared = LiquidPlayerController()
    /// Called when the player is closed, so the shell can bring the player back in the notch.
    var onReturnToNotch: () -> Void = {}

    @Published private(set) var height = LiquidPlayerPolicy.size(for: .player).height
    @Published private(set) var panel: LiquidPlayerPanel = .cover
    /// 0...1 while the card is being pulled out of the notch (it fades and scales in); 1 at rest.
    @Published private(set) var dragProgress: CGFloat = 1
    private(set) var isVisible = false

    private var window: LiquidPlayerWindow?
    private var scrollMonitor: Any?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var isDropDown = false
    private var hideTimer: Timer?
    private var gestureVelocity: CGFloat = 0
    private let model: NowPlayingModel

    override init() {
        self.model = .shared
        super.init()
    }

    /// Call once at launch: wires the menu-bar item to the settings and the playing song.
    func start() {
        guard cancellables.isEmpty else { return }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncMenuBarItem() }.store(in: &cancellables)
        model.$track.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenuBarTitle() }.store(in: &cancellables)
        syncMenuBarItem()
    }

    func stop() {
        cancellables.removeAll()
        close(returning: false)
        removeStatusItem()
    }

    // MARK: Show / hide

    func toggle() {
        if isVisible { close(returning: false) } else { present(kind: AppSettings.shared.liquidPlayerSize, topLeft: nil, dropDown: false) }
    }

    func close(returning: Bool = true) {
        removePopDragMonitors()
        dragProgress = 1
        hideTimer?.invalidate()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        window?.orderOut(nil)
        window = nil
        let wasVisible = isVisible
        isVisible = false
        isDropDown = false
        if returning, wasVisible { onReturnToNotch() }
    }

    private func present(kind: LiquidPlayerSize, topLeft: CGPoint?, dropDown: Bool) {
        close(returning: false)
        height = LiquidPlayerPolicy.size(for: kind).height
        panel = .cover
        isDropDown = dropDown
        let window = LiquidPlayerWindow()
        window.level = AppSettings.shared.liquidPlayerFloatsOverApps
            ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.contentView = NSHostingView(rootView: LiquidPlayerRoot(controller: self, model: model))
        let origin = topLeft ?? AppSettings.shared.liquidPlayerOrigin ?? defaultTopLeft()
        window.setFrame(frame(topLeft: origin, height: height), display: false)
        window.orderFrontRegardless()
        self.window = window
        isVisible = true
        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved), name: NSWindow.didMoveNotification, object: window)
        installScrollMonitor()
        if dropDown { scheduleAutoHide() }
    }

    private func defaultTopLeft() -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visible.maxX - 360, y: visible.maxY - 12)
    }

    private func frame(topLeft: CGPoint, height: CGFloat) -> CGRect {
        let size = CGSize(width: LiquidPlayerPolicy.width(forHeight: height), height: height)
        let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
        return LiquidPlayerPolicy.frame(topLeft: topLeft, size: size, in: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @objc private func windowMoved() {
        guard let window, !isDropDown else { return }
        AppSettings.shared.liquidPlayerOrigin = CGPoint(x: window.frame.minX, y: window.frame.maxY)
    }

    // MARK: Pull out of the notch

    private struct PopDrag {
        let start: CGPoint
        var last: CGPoint
        var lastTime: TimeInterval
        /// Downward, points per second, smoothed.
        var velocity: CGFloat = 0
    }
    private var popDrag: PopDrag?
    private var popDragMonitors: [Any] = []

    /// Starts the interactive pull: the card appears under the pointer and follows it until release.
    /// `translation` is the SwiftUI drag so far (y down), so the pull is measured from the press.
    func beginPopOutDrag(translation: CGSize) {
        guard !isVisible, popDrag == nil, model.track != nil else { return }
        let pointer = NSEvent.mouseLocation
        let start = CGPoint(x: pointer.x - translation.width, y: pointer.y + translation.height)
        present(kind: .player, topLeft: LiquidPopOutDrag.topLeft(pointer: pointer, width: LiquidPlayerPolicy.size(for: .player).width),
                dropDown: false)
        dragProgress = 0
        window?.level = .popUpMenu
        window?.ignoresMouseEvents = true
        popDrag = PopDrag(start: start, last: pointer, lastTime: ProcessInfo.processInfo.systemUptime)
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseUp { self?.endPopOutDrag() } else { self?.trackPopOutDrag() }
            }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        popDragMonitors = [NSEvent.addLocalMonitorForEvents(matching: mask) { handler($0); return $0 } as Any,
                           NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) as Any]
        trackPopOutDrag()
    }

    private func trackPopOutDrag() {
        guard var drag = popDrag, let window else { return }
        let pointer = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - drag.lastTime
        if elapsed > 0.001 {
            let instant = (drag.last.y - pointer.y) / CGFloat(elapsed)
            drag.velocity = drag.velocity * 0.6 + instant * 0.4
        }
        drag.last = pointer
        drag.lastTime = now
        popDrag = drag
        let pull = drag.start.y - pointer.y
        height = LiquidPopOutDrag.height(pull: pull)
        dragProgress = LiquidPopOutDrag.progress(pull: pull)
        let topLeft = LiquidPopOutDrag.topLeft(pointer: pointer, width: LiquidPlayerPolicy.width(forHeight: height))
        window.setFrame(frame(topLeft: topLeft, height: height), display: true)
    }

    private func endPopOutDrag() {
        guard let drag = popDrag, let window else { return }
        removePopDragMonitors()
        window.ignoresMouseEvents = false
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pull = drag.start.y - drag.last.y
        guard LiquidPopOutDrag.commits(pull: pull, velocity: drag.velocity) else {
            // Not far enough: the card slides back up into the notch and is gone.
            withAnimation(reduce ? nil : .easeIn(duration: 0.18)) { dragProgress = 0 }
            var home = window.frame
            home.origin.y = min(drag.start.y - home.height / 2, (window.screen?.frame.maxY ?? home.maxY) - home.height)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduce ? 0 : 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(home, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { if self?.window === window { self?.close(returning: false) } }
            })
            return
        }
        window.level = AppSettings.shared.liquidPlayerFloatsOverApps
            ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        withAnimation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { dragProgress = 1 }
        settle(on: LiquidPopOutDrag.settledSize(height: height, velocity: drag.velocity))
    }

    private func removePopDragMonitors() {
        popDragMonitors.forEach(NSEvent.removeMonitor)
        popDragMonitors = []
        popDrag = nil
    }

    // MARK: Sizing

    func cycleSize() { settle(on: LiquidPlayerPolicy.next(LiquidPlayerPolicy.snap(height: height))) }

    func choosePanel(_ next: LiquidPlayerPanel) {
        panel = next
        if next != .cover, LiquidPlayerPolicy.layout(forHeight: height) != .expanded { settle(on: .expanded) }
    }

    private func settle(on kind: LiquidPlayerSize) {
        guard let window else { return }
        let target = LiquidPlayerPolicy.size(for: kind).height
        let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        AppSettings.shared.liquidPlayerSize = kind
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? nil : .spring(response: 0.42, dampingFraction: 0.84)) { height = target }
        let next = frame(topLeft: topLeft, height: target)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : 0.34
            // A soft overshoot-free spring curve, so the window lands like the SwiftUI surface does.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            window.animator().setFrame(next, display: true)
        }
        if kind != .expanded { panel = .cover }
    }

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return handleScroll(event) ? nil : event
        }
    }

    /// Two-finger vertical swipe: the window edge follows the fingers; releasing snaps to a size.
    /// A mouse wheel steps one size per notch.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        if !event.hasPreciseScrollingDeltas {
            guard event.scrollingDeltaY != 0 else { return false }
            settle(on: LiquidPlayerPolicy.stepped(LiquidPlayerPolicy.snap(height: height), larger: event.scrollingDeltaY > 0))
            return true
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let velocity = gestureVelocity
            let wasResizing = isResizing
            gestureVelocity = 0
            isResizing = false
            guard wasResizing else { return false }
            settle(on: LiquidPlayerPolicy.snap(height: height, velocity: velocity))
            return true
        }
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) || isResizing,
              !event.momentumPhase.contains(.changed) else { return isResizing }
        isResizing = true
        gestureVelocity = -event.scrollingDeltaY
        height = LiquidPlayerPolicy.height(afterScrollDeltaY: event.scrollingDeltaY, from: height)
        window.setFrame(frame(topLeft: CGPoint(x: window.frame.minX, y: window.frame.maxY), height: height), display: true)
        return true
    }
    private var isResizing = false

    // MARK: Menu-bar mode

    private func syncMenuBarItem() {
        if AppSettings.shared.liquidPlayerMenuBarMode, model.track != nil || statusItem != nil {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked)
                item.button?.imagePosition = .imageLeading
                statusItem = item
            }
            refreshMenuBarTitle()
        } else { removeStatusItem() }
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func refreshMenuBarTitle() {
        guard let button = statusItem?.button else { syncMenuBarItem(); return }
        guard let track = model.track else { statusItem?.isVisible = false; return }
        statusItem?.isVisible = true
        button.image = track.artwork.map { Self.menuBarImage($0) } ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Now playing")
        button.title = AppSettings.shared.liquidPlayerShowsSongInMenuBar
            ? " " + Self.menuBarText(title: track.title, artist: track.artist) : ""
    }

    nonisolated static func menuBarText(title: String, artist: String, limit: Int = 32) -> String {
        let text = artist.isEmpty ? title : "\(title) — \(artist)"
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    private static func menuBarImage(_ art: NSImage) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            art.draw(in: rect)
            return true
        }
    }

    @objc private func statusItemClicked() {
        if isVisible { close(returning: false); return }
        guard let button = statusItem?.button, let host = button.window else { return }
        let frame = host.convertToScreen(button.convert(button.bounds, to: nil))
        let width = LiquidPlayerPolicy.width(forHeight: LiquidPlayerPolicy.size(for: AppSettings.shared.liquidPlayerSize).height)
        present(kind: AppSettings.shared.liquidPlayerSize, topLeft: CGPoint(x: frame.midX - width / 2, y: frame.minY - 6), dropDown: true)
    }

    /// The drop-down hides 3 s after the pointer leaves it; moving back in cancels that.
    private func scheduleAutoHide() {
        guard AppSettings.shared.liquidPlayerAutoHides else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { timer.invalidate(); return }
                if window.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) { self.outsideSince = nil; return }
                let since = self.outsideSince ?? Date()
                self.outsideSince = since
                if Date().timeIntervalSince(since) >= 3 { timer.invalidate(); self.close(returning: false) }
            }
        }
    }
    private var outsideSince: Date?
}

/// Hosts the SwiftUI player; reads the controller's height so the surface morphs with the window.
private struct LiquidPlayerRoot: View {
    @ObservedObject var controller: LiquidPlayerController
    @ObservedObject var model: NowPlayingModel

    var body: some View {
        LiquidPlayerView(model: model, height: controller.height,
                         onClose: { controller.close() }, onCycle: controller.cycleSize,
                         onChoosePanel: controller.choosePanel, panel: controller.panel)
            .scaleEffect(0.86 + 0.14 * controller.dragProgress, anchor: .top)
            .opacity(Double(min(1, controller.dragProgress * 1.3)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A borderless, non-activating panel: clicking the player never steals focus from the app in front.
final class LiquidPlayerWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
