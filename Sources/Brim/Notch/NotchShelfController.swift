import AppKit
import Combine
import SwiftUI

/// The three shelves of the Tray page.
enum TrayTab: String, CaseIterable, Identifiable {
    case files = "Files", clipboard = "Clipboard", share = "Share"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .files: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .share: return "square.and.arrow.up"
        }
    }
}

@MainActor
final class NotchPresentation: ObservableObject {
    @Published var isExpanded = false
    @Published var selectedActivity: IslandActivity?
    /// Home was tapped since the island opened: show the widgets even while an activity leads.
    @Published var homeTapped = false
    var activities = IslandActivities(recording: false, call: false, music: false)
    @Published var isPresentingConfirmation = false
    @Published var isPresentingCallConfirmation = false
    @Published var isPresentingLibraryConfirmation = false
    @Published var isPresentingAudioOutputs = false
    @Published var isShowingLibrary = false
    @Published var isShowingActivities = false
    @Published var toolActivity: IslandActivity?
    /// The widget open on the Widgets page (nil shows the grid).
    @Published var openWidget: IslandWidgetTile?
    @Published var isShowingSharing = false
    @Published var isShowingCalendar = false
    /// The Music page (the full player) is open.
    @Published var isShowingMusic = false
    @Published var isShowingMessages = false
    @Published var trayTab: TrayTab = .clipboard
    /// The library was opened from the Clipboard button rather than Library.
    @Published var openedFromClipboard = false
    /// Files are being dragged near the notch: show Keep, AirDrop and Convert.
    @Published var isShowingDropTargets = false
    /// Files dropped on Convert, waiting for a format choice.
    @Published var convertURLs: [URL] = []
    /// Files on their way to a nearby device with LocalSend (the tray's quick action).
    @Published var localSendURLs: [URL] = []
    @Published var geometry = NotchGeometry(screenFrame: .zero, notchWidth: 0, notchHeight: 0)
    /// Elastic horizontal offset of the open island's content while a page swipe is in flight.
    @Published var pageDrag: CGFloat = 0
    /// The live activity a closed-island flick put on the notch (Multi Live Activities).
    @Published var leader: IslandActivity?
    /// The detached bubbles and their sides, kept from update to update so they never swap.
    @Published private(set) var bubbles = IslandBubblePair.none
    /// Set by NotchShelfView: moves the open island by whole pages.
    var stepPage: ((Int) -> Void)?
    /// Music is dropped from the island while another app is fullscreen (Settings > Media).
    @Published var mediaHidden = false
    /// The island was opened onto a notification card and closes when that card goes away.
    @Published var expandedForNotification = false
    /// Elastic pull of the compact artwork while a track swipe is in flight.
    @Published var trackStretch: CGFloat = 0
    /// Where the navigation capsule was last laid out, in the island window's top-left coordinates.
    /// Not published: hit testing reads it, the view never re-renders from it.
    var capsuleFrameInWindow: CGRect?
    /// HUD flashes are drawn on another display (Settings > HUDs > Show on).
    @Published var hudElsewhere = false

    func updateActivities(_ next: IslandActivities, route nextRoute: CompactRoute? = nil) {
        let route = nextRoute ?? geometry.route
        guard activities != next || geometry.route != route else { return }
        let urgentArrival = activities.primary != next.primary
            && (next.primary == .recording || next.primary == .call)
        let selectionEnded = selectedActivity.map { !next.available.contains($0) } ?? false
        if urgentArrival || selectionEnded {
            selectedActivity = nil
            isPresentingAudioOutputs = false
        }
        activities = next
        geometry.route = route
        geometry.hasLiveActivity = next.primary != nil
        geometry.compactActivity = next.primary
        let beside = next.islandOwner(expanded: isExpanded, selected: selectedActivity, showingMusic: isShowingMusic)
        setBubbles(next.companions(to: beside), route: route)
        geometry.secondaryActivity = next.companion(to: beside)
    }

    /// The bubbles beside the island. A bubble already showing keeps its side; see
    /// `IslandBubblePair.placing`. HUDs and notifications own the closed island; the bubbles wait.
    func setBubbles(_ companions: [IslandActivity], route: CompactRoute) {
        let pair = IslandBubblePair.placing(companions, after: bubbles)
        if bubbles != pair { bubbles = pair }
        let allowed = !route.isHUD && route != .notification
        let leading = allowed && pair.leading != nil
        let trailing = allowed && pair.trailing != nil
        if geometry.hasLeadingBubble != leading { geometry.hasLeadingBubble = leading }
        if geometry.hasSecondaryActivity != trailing { geometry.hasSecondaryActivity = trailing }
    }

    /// The activity in the bubble on `side`, as it is laid out right now.
    func bubbleActivity(_ side: IslandBubbleSide) -> IslandActivity? { bubbles.activity(on: side) }

    /// A bubble was clicked or hovered open: the song's opens the Music page, any other its card.
    func showBubble(_ activity: IslandActivity) {
        if activity == .music {
            navigate(to: .showing(.music))
        } else {
            selectedActivity = activity
        }
    }
}

/// Key focus is available to the library's search field after a click, never on hover.
final class IslandPanel: NSPanel {
    /// Only an open island may take key focus (library search, notification reply); the closed
    /// island's HUD card and glances are click-only and must never steal it from the front app.
    var keyAllowed = false
    override var canBecomeKey: Bool { keyAllowed }
    override var canBecomeMain: Bool { false }

    /// The island's window: borderless, non-activating, above the menu bar, on every Space.
    static func make(frame: CGRect) -> IslandPanel {
        let window = IslandPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.sharingType = AppSettings.shared.shellHideFromCapture ? .none : .readOnly
        return window
    }

    /// The SwiftUI host the island draws into. AppKit owns the fixed canvas, so SwiftUI's
    /// intrinsic/min/max size probes are skipped.
    static func host<Content: View>(_ root: Content) -> NSView {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        return host
    }
}

@MainActor
final class NotchShelfController: NSObject {
    static let shared = NotchShelfController()

    @MainActor
    private final class Surface {
        let presentation: NotchPresentation
        let panel: NSPanel
        var hover = ShelfHoverState()
        var announcement = IslandAnnouncement()
        var transitionID = 0
        let displayID: CGDirectDisplayID?
        let displayUUID: String?
        let isExternal: Bool
        var visibility = ShellVisibility.visible
        /// Opened by shortcut away from the pointer: stays open until the pointer visits and leaves.
        var pinnedOpen = false
        var hiddenUntil: TimeInterval?
        /// Opened on purpose (a shortcut, a click, a widget asking): shows even over a fullscreen app
        /// until it closes again.
        var summoned = false
        var pageSwipe = SwipeTracker()
        var swipeGate = IslandSwipeGate()
        var flick = SwipeTracker(commitDistance: 30)
        var targetAlpha: CGFloat = 1
        var trackSwipe = SwipeTracker(commitDistance: 44)
        var holdsNotification = false
        var pointerHold = IslandPointerHold()
        /// The typing widget the panel was last made key for, so focus is taken once per opening.
        var focusedWidget: IslandWidgetTile?
        /// Whether the HUD shows its card: on hover, or by itself for flashes that ask (AirPods connect).
        var hudCard = HUDAutoCard()
        var hudHeld = false
        /// The page the island last closed on; a plain hover reopens there.
        var lastNavigation: IslandNavigation?
        init(presentation: NotchPresentation, panel: NSPanel, displayID: CGDirectDisplayID?, isExternal: Bool) {
            self.presentation = presentation
            self.panel = panel
            self.displayID = displayID
            self.displayUUID = displayID.flatMap(ShellEnvironment.displayUUID)
            self.isExternal = isExternal
        }
    }

    private var surfaces: [Surface] = []
    private var timer: Timer?
    /// Counts ticks so an idle island can skip most of them.
    private var tickCount = 0
    private var suspended = false
    private var displayObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []
    private let environment = ShellEnvironment()
    private let input = ShellInputMonitor()
    private let menuBarBand = MenuBarBandController()
    /// Set by the Island Tour: this island stays open while a step needs it.
    private weak var tourHeld: NotchPresentation?
    /// The island the tour pinned until the pointer visits and leaves (its "close it now" step).
    private weak var tourPinned: NotchPresentation?
    /// Where the Island Tour's card sits on screen; a click there never closes the island.
    var tourCardFrame: CGRect?

    func start() {
        guard timer == nil else { return }
        rebuildPanels()
        IslandTheme.shared.startMonitoring()
        menuBarBand.update(enabled: AppSettings.shared.shellHidePhysicalNotch)
        observeMenus()
        startShellInput()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRebuild() }
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        trackingMenus.removeAll()
        removePanels()
        menuBarBand.update(enabled: false)
        IslandTheme.shared.stopMonitoring()
        input.stop()
        ShellHotkey.shared.unregister()
    }

    /// Applies every setting live: size sliders, style, capture hiding and the shortcut.
    func settingsChanged() {
        guard AppSettings.shared.notchShelfEnabled else { stop(); return }
        if timer == nil { start() } else { refreshSurfaces() }
        menuBarBand.update(enabled: AppSettings.shared.shellHidePhysicalNotch)
        updateHotkey()
    }

    func suspend() {
        suspended = true
        dismissShelf()
        surfaces.forEach { $0.panel.orderOut(nil) }
    }

    func resume() {
        suspended = false
        guard AppSettings.shared.notchShelfEnabled else { return }
        surfaces.forEach { $0.panel.orderFrontRegardless() }
    }

    func dismissShelf() {
        for surface in surfaces {
            surface.hover.reset()
            surface.announcement.dismiss()
            surface.pinnedOpen = false
            setExpanded(false, on: surface)
        }
    }

    /// Opens the notch on the display with the pointer, showing the convert card for these files.
    func presentConvert(_ urls: [URL]) {
        let pointer = NSEvent.mouseLocation
        guard !urls.isEmpty,
              let surface = surfaces.first(where: { $0.presentation.geometry.screenFrame.contains(pointer) })
                ?? surfaces.first else { return }
        surface.presentation.convertURLs = urls
        setExpanded(true, on: surface)
    }

    /// Opens the island on LocalSend's nearby devices for these files.
    func presentLocalSend(_ urls: [URL]) {
        let pointer = NSEvent.mouseLocation
        guard !urls.isEmpty,
              let surface = surfaces.first(where: { $0.presentation.geometry.screenFrame.contains(pointer) })
                ?? surfaces.first else { return }
        surface.presentation.convertURLs = []
        surface.presentation.isShowingDropTargets = false
        surface.presentation.localSendURLs = urls
        open(surface, pinned: true)
    }

    /// Opens the island on the clipboard library, on the display under the pointer (⌥⇧Space).
    func presentClipboard() {
        let pointer = NSEvent.mouseLocation
        guard let surface = surfaces.first(where: { $0.presentation.geometry.screenFrame.contains(pointer) })
            ?? surfaces.first else { return }
        let presentation = surface.presentation
        presentation.homeTapped = false
        presentation.isShowingActivities = false
        presentation.isShowingCalendar = false
        presentation.isShowingMusic = false
        presentation.isShowingMessages = false
        presentation.selectedActivity = nil
        presentation.isShowingLibrary = true
        presentation.openedFromClipboard = true
        presentation.trayTab = .clipboard
        setExpanded(true, on: surface)
    }

    /// True while any display's island is open (the spacebar play/pause shortcut needs it).
    var isAnyIslandOpen: Bool { surfaces.contains { $0.presentation.isExpanded } }

    /// Opens the island on one widget, on the display under the pointer (Text Capture results,
    /// droplet shortcuts). It stays open until the pointer visits and leaves.
    func presentWidget(_ tile: IslandWidgetTile) {
        let pointer = NSEvent.mouseLocation
        guard tile.opensInIsland,
              let surface = surfaces.first(where: { $0.presentation.geometry.screenFrame.contains(pointer) })
                ?? surfaces.first else { return }
        surface.presentation.selectedActivity = nil
        surface.presentation.navigate(to: .opening(tile))
        open(surface, pinned: true)
    }

    func edit(_ entry: ShelfEntry) {
        guard let image = ShelfStore.shared.image(for: entry) else { return }
        dismissShelf()
        let editedID = UUID()
        ShelfEditorWindowController.open(image: image) { image in
            ShelfEditorWindowController.keepEdited(image, id: editedID)
        }
    }

    func save(_ entry: ShelfEntry) {
        guard let image = ShelfStore.shared.image(for: entry) else { return }
        dismissShelf()
        CaptureActions.save(image, from: nil, forceSavePanel: true)
    }

    // MARK: - Settings, input and shortcut

    /// Re-measures every display and applies size tuning in place; rebuilds only if the display set changed.
    private func refreshSurfaces() {
        let screens = NSScreen.screens
        guard screens.count == surfaces.count else { rebuildPanels(); return }
        for (surface, screen) in zip(surfaces, screens) {
            let next = ShellEnvironment.geometry(for: screen)
            var geometry = surface.presentation.geometry
            geometry.screenFrame = next.screenFrame
            geometry.notchWidth = next.notchWidth
            geometry.notchHeight = next.notchHeight
            geometry.topInset = next.topInset
            geometry.isSimulatedNotch = next.isSimulatedNotch
            geometry.tuning = next.tuning
            surface.presentation.geometry = geometry
            surface.panel.setFrame(geometry.hostingFrame, display: true)
            surface.panel.sharingType = AppSettings.shared.shellHideFromCapture ? .none : .readOnly
        }
    }

    private func updateHotkey() {
        if AppSettings.shared.shellToggleHotkeyEnabled {
            ShellHotkey.shared.onToggle = { [weak self] in self?.toggleUnderPointer() }
            ShellHotkey.shared.register()
        } else {
            ShellHotkey.shared.unregister()
        }
    }

    private func startShellInput() {
        input.onLeftClick = { [weak self] point in self?.handleClick(at: point) }
        input.onRightClick = { [weak self] point in self?.handleRightClick(at: point) }
        input.onScroll = { [weak self] dx, dy, phase, point in self?.handleScroll(dx: dx, dy: dy, phase: phase, at: point) }
        input.start()
        updateHotkey()
    }

    /// True when the point is on an island's current outline (drag-out tracking).
    func islandContains(_ point: CGPoint) -> Bool { surface(at: point) != nil }

    private func surface(at point: CGPoint) -> Surface? {
        surfaces.first { $0.presentation.geometry.containsPointer(point, expanded: $0.presentation.isExpanded) }
    }

    private func open(_ surface: Surface, pinned: Bool) {
        surface.hover.forceOpen()
        surface.pinnedOpen = pinned
        setExpanded(true, on: surface)
    }

    private func close(_ surface: Surface) {
        surface.hover.reset()
        surface.announcement.dismiss()
        surface.pinnedOpen = false
        setExpanded(false, on: surface)
    }

    /// ⌥⌘N: open or close the island on the display under the pointer.
    func toggleUnderPointer() {
        let pointer = NSEvent.mouseLocation
        guard let target = surfaces.first(where: { $0.presentation.geometry.screenFrame.contains(pointer) }) ?? surfaces.first
        else { return }
        target.hiddenUntil = nil
        if target.presentation.isExpanded { close(target) } else { open(target, pinned: true) }
    }

    /// Clicking the collapsed notch opens it even when hover-open is off; with auto-collapse off,
    /// clicking anywhere else closes it.
    private func handleClick(at point: CGPoint) {
        guard !suspended else { return }
        for surface in surfaces where surface.visibility != .hidden {
            let geometry = surface.presentation.geometry
            if surface.presentation.isExpanded {
                let manualClose = surface.pinnedOpen || !AppSettings.shared.shellAutoCollapse || isTyping(on: surface)
                let onTourCard = tourCardFrame?.contains(point) == true
                if manualClose && !onTourCard && !geometry.containsPointer(point, expanded: true) { close(surface) }
            } else if geometry.containsPointer(point, expanded: false) {
                if geometry.hudHovered { continue }  // the HUD card's own buttons take this click
                // A bubble opens its own activity, whatever the island's click setting does.
                if let side = geometry.bubble(at: point, expanded: false),
                   let activity = surface.presentation.bubbleActivity(side) {
                    surface.presentation.showBubble(activity)
                    open(surface, pinned: false)
                    continue
                }
                if geometry.route.isAgentNeedingInput(surface.presentation.activities),
                   CodingAgentModel.shared.jumpToAttention() { continue }
                // Settings > Media: a click on the playing song can play/pause or open its app instead.
                if geometry.route == .activity(.music), NotchMusicClick.handle() { continue }
                perform(NotchClickResolver.resolve(action: AppSettings.shared.shellClickAction,
                                                   page: AppSettings.shared.shellClickPage), on: surface)
            }
        }
    }

    /// Settings > Island > "On notch click".
    private func perform(_ outcome: NotchClickOutcome, on surface: Surface) {
        switch outcome {
        case .open:
            open(surface, pinned: false)
        case .openPage(let page):
            surface.presentation.selectedActivity = nil
            surface.presentation.navigate(to: .showing(page))
            open(surface, pinned: false)
        case .togglePlayback:
            NowPlayingModel.shared.playPause()
            ShellHaptics.tick()
        case .ignore:
            break
        }
    }

    private func handleRightClick(at point: CGPoint) {
        guard !suspended, let surface = surfaces.first(where: {
            !$0.presentation.isExpanded && $0.presentation.geometry.containsPointer(point, expanded: false)
        }) else { return }
        if surface.hiddenUntil != nil { surface.hiddenUntil = nil; return }
        switch AppSettings.shared.shellRightClickAction {
        case .openSettings: SettingsWindowController.shared.show()
        case .hide: surface.hiddenUntil = ProcessInfo.processInfo.systemUptime + 3600
        case .none: break
        }
    }

    /// Two fingers on the open island turn pages; on the closed island they swap which of two live
    /// activities owns the notch.
    private func handleScroll(dx: CGFloat, dy: CGFloat, phase: SwipeTracker.Phase, at point: CGPoint) {
        guard !suspended, let surface = surface(at: point), surface.visibility != .hidden else { return }
        let presentation = surface.presentation
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if presentation.isExpanded {
            guard AppSettings.shared.shellSwipeNavigation else { return }
            // Content that scrolls sideways keeps the gesture; only edges, plain content and the tab bar turn pages.
            guard surface.swipeGate.allows(dx: dx, dy: dy, phase: phase, region: { IslandScrollRegions.shared.region(atScreen: point) })
            else { return }
            switch surface.pageSwipe.feed(dx: dx, dy: dy, phase: phase) {
            case .dragging(let offset): presentation.pageDrag = reduce ? 0 : offset
            case .commit(let delta):
                ShellHaptics.tick()
                withAnimation(NotchMotion.layout(reduceMotion: reduce)) { presentation.pageDrag = 0 }
                presentation.stepPage?(delta)
            case .cancelled:
                withAnimation(NotchMotion.layout(reduceMotion: reduce)) { presentation.pageDrag = 0 }
            case .none: break
            }
        } else if presentation.geometry.route == .activity(.music), !presentation.geometry.hasBubble,
                  AppSettings.shared.trackSwipeEnabled {
            handleTrackSwipe(dx: dx, dy: dy, phase: phase, reduce: reduce, surface: surface)
        } else if presentation.geometry.hasBubble {
            if case .commit = surface.flick.feed(dx: dx, dy: dy, phase: phase), let next = presentation.activities.secondary {
                ShellHaptics.tick()
                withAnimation(NotchMotion.layout(reduceMotion: reduce)) { presentation.leader = next }
            }
        }
    }

    /// Two-finger swipe on the compact music island: next/previous track with an elastic pull on the artwork.
    private func handleTrackSwipe(dx: CGFloat, dy: CGFloat, phase: SwipeTracker.Phase, reduce: Bool, surface: Surface) {
        let presentation = surface.presentation
        let settle = { withAnimation(reduce ? nil : .spring(duration: 0.3, bounce: 0.3)) { presentation.trackStretch = 0 } }
        switch surface.trackSwipe.feed(dx: dx, dy: dy, phase: phase) {
        case .dragging(let offset):
            presentation.trackStretch = reduce ? 0 : offset / SwipeTracker.maxStretch * TrackSwipeTracker.maxStretch
        case .commit(let delta):
            ShellHaptics.tick()
            let next = (delta > 0) != AppSettings.shared.reverseSwipeDirection
            next ? NowPlayingModel.shared.next() : NowPlayingModel.shared.previous()
            settle()
        case .cancelled: settle()
        case .none: break
        }
    }

    private func removePanels() {
        for surface in surfaces {
            surface.panel.orderOut(nil)
            surface.panel.contentView = nil
        }
        surfaces.removeAll()
        trackingMenus.removeAll()
    }

    private var rebuildGeneration = 0

    /// Display changes arrive in bursts (wake, a dock, a resolution switch); rebuild once they settle.
    private func scheduleRebuild() {
        rebuildGeneration += 1
        let generation = rebuildGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.rebuildGeneration == generation else { return }
            self.rebuildPanels()
        }
    }

    private func rebuildPanels() {
        removePanels()
        guard AppSettings.shared.notchShelfEnabled else { return }
        // One independent hover surface per physical display, sharing the same content models.
        for screen in NSScreen.screens {
            let geometry = ShellEnvironment.geometry(for: screen)
            let presentation = NotchPresentation()
            presentation.geometry = geometry
            let window = IslandPanel.make(frame: geometry.hostingFrame)
            window.contentView = IslandPanel.host(NotchShelfView(presentation: presentation, store: .shared))
            surfaces.append(Surface(presentation: presentation, panel: window,
                                    displayID: ShellEnvironment.displayID(of: screen),
                                    isExternal: ShellEnvironment.hardwareNotch(of: screen) == nil))
            if !suspended { window.orderFrontRegardless() }
        }
    }

    private func tick() {
        guard !suspended, AppSettings.shared.notchShelfEnabled else { return }
        let pointer = NSEvent.mouseLocation
        // Closed and the pointer nowhere near an island: run at 10 Hz and sample the window list
        // less often. Hover, animations and open islands keep the full 30 Hz.
        let idle = isIdle(pointer: pointer)
        tickCount &+= 1
        if idle && tickCount % 3 != 0 { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        environment.refresh(screens: NSScreen.screens, now: uptime, interval: idle ? 0.8 : 0.4)
        let timing = ShellTiming.current()
        let displays = HUDDisplayPolicy.liveDisplays()
        let hudTarget = AppSettings.shared.hudDisplayTarget
        for surface in surfaces {
            let presentation = surface.presentation
            let hudElsewhere = surface.displayID.map {
                !HUDDisplayPolicy.shows(on: Int($0), target: hudTarget, pointer: pointer, displays: displays)
            } ?? false
            if presentation.hudElsewhere != hudElsewhere { presentation.hudElsewhere = hudElsewhere }
            if presentation.geometry.hudPlacement != AppSettings.shared.hudPlacement {
                presentation.geometry.hudPlacement = AppSettings.shared.hudPlacement
            }
            let hideMedia = MediaIslandPolicy.shouldHideMedia(
                frontAppIsFullscreen: environment.state(for: surface.displayID).coveredByFullscreen)
            if presentation.mediaHidden != hideMedia { presentation.mediaHidden = hideMedia }
            let activities = IslandActivities(recording: ScreenRecordingModel.shared.activeRecording != nil,
                call: CallActivityModel.shared.activeCall != nil,
                music: NowPlayingModel.shared.isInIsland() && !hideMedia,
                timer: NativeTimerModel.shared.activeTimer != nil,
                agentNeedsInput: ActivityCenter.shared.coding.sessions.contains { $0.needsAttention && $0.isLive() },
                additional: ActivityCenter.shared.activeKinds.filter { !hudElsewhere || $0 != .system },
                leader: presentation.leader)
            let route = CompactRoute.resolve(
                activities: activities, flash: hudElsewhere ? nil : IslandFlashCenter.shared.current,
                hasNotification: NotificationHUDModel.shared.current != nil)
            if presentation.activities != activities || presentation.geometry.route != route {
                withAnimation(NotchMotion.layout(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                    presentation.updateActivities(activities, route: route)
                }
            }
            surface.visibility = ShellVisibilityPolicy.decide(visibilityContext(for: surface, now: uptime))
            if surface.visibility == .hidden {
                suppress(surface)
                continue
            }
            tickVisible(surface, activities: activities, pointer: pointer, now: uptime, timing: timing)
        }
    }

    private func visibilityContext(for surface: Surface, now: TimeInterval) -> ShellVisibilityContext {
        let settings = AppSettings.shared
        let display = environment.state(for: surface.displayID)
        if let until = surface.hiddenUntil, now >= until { surface.hiddenUntil = nil }
        return ShellVisibilityContext(
            isExternalDisplay: surface.isExternal, externalMode: settings.shellExternalVisibility,
            hasLiveActivity: surface.presentation.activities.primary != nil,
            hideOnFullscreen: settings.shellHideOnFullscreen, displayHasFullscreenWindow: display.hasFullscreenWindow,
            hideInMissionControl: settings.shellHideInMissionControl, missionControlActive: display.missionControlActive,
            hiddenAppBundleIDs: Set(settings.shellHiddenApps), frontmostBundleID: environment.frontmostBundleID,
            hiddenUntil: surface.hiddenUntil, now: now, summoned: surface.summoned,
            displayDisabled: surface.displayUUID.map { settings.shellDisabledDisplays.contains($0) } ?? false)
    }

    /// Hidden by policy: collapse, stop listening for the pointer, and fade out.
    private func suppress(_ surface: Surface) {
        if surface.presentation.isExpanded || surface.hover.isExpanded {
            surface.hover.reset()
            surface.announcement.dismiss()
            surface.pinnedOpen = false
            setExpanded(false, on: surface)
        }
        surface.panel.ignoresMouseEvents = true
        setAlpha(0, on: surface)
    }

    private func setAlpha(_ alpha: CGFloat, on surface: Surface) {
        guard surface.targetAlpha != alpha else { return }
        surface.targetAlpha = alpha
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : 0.18 * AppSettings.shared.shellAnimationSpeed.durationScale
            surface.panel.animator().alphaValue = alpha
        }
    }

    /// Nothing is open or opening and the pointer is away from the top of every island's display.
    private func isIdle(pointer: CGPoint) -> Bool {
        surfaces.allSatisfy { surface in
            let presentation = surface.presentation
            guard !presentation.isExpanded, !surface.hover.isExpanded, !surface.summoned else { return false }
            // Explicit bounds: `CGRect.contains` excludes the top edge, where the pointer rests to
            // reach the notch.
            let frame = presentation.geometry.screenFrame
            return pointer.x < frame.minX || pointer.x > frame.maxX || pointer.y < frame.maxY - 160
        }
    }

    private func tickVisible(_ surface: Surface, activities: IslandActivities, pointer: CGPoint,
                             now: TimeInterval, timing: ShellTiming) {
        let presentation = surface.presentation
        let geometry = presentation.geometry
        let announcing = AppSettings.shared.shellAutoExpandActivities
            && surface.announcement.update(primary: activities.primary, now: now)
            && !presentation.isShowingLibrary
        let pointerInside = geometry.containsPointer(pointer, expanded: presentation.isExpanded)
        // A page switch or an opened widget resizes the island under a still pointer: not a leave.
        // Drifting a little past the open island (under the tabs, off a corner) is not a leave either.
        let nearOpen = presentation.isExpanded && geometry.keepsOpen(pointer)
        let inside = surface.pointerHold.update(pointer: pointer, inside: pointerInside || nearOpen,
                                                expanded: presentation.isExpanded, reach: geometry.openReach)
        if surface.pinnedOpen && pointerInside { surface.pinnedOpen = false }
        let busy = NSEvent.pressedMouseButtons != 0 || !trackingMenus.isEmpty
            || presentation.isPresentingConfirmation || presentation.isPresentingCallConfirmation
            || presentation.isPresentingLibraryConfirmation
            || ActivityCenter.shared.sharing.isPresenting || ActivityCenter.shared.calendar.isWorking
            || ActivityCenter.shared.agent.isPresenting
            || ScreenRecordingModel.shared.isWorking || NativeTimerModel.shared.isWorking
        // The notification card's link panel or an in-flight reply keeps the island open like a typing widget.
        let typing = isTyping(on: surface)
            || (presentation.isExpanded && presentation.expandedForNotification && NotificationHUDModel.shared.holdsIslandOpen)
        let hudClosed = geometry.route.isHUD && !presentation.isExpanded && !surface.pinnedOpen
        let hovering: Bool
        if hudClosed {
            // A HUD on the closed island answers hover with its card, never with the full island.
            surface.hover.reset()
            hovering = false
            let card = surface.hudCard.update(flash: geometry.route.hudFlash, hovered: inside, now: now)
            setHUDHover(card, held: inside, on: surface)
        } else {
            _ = surface.hudCard.update(flash: geometry.route.hudFlash, hovered: false, now: now)
            setHUDHover(false, held: false, on: surface)
            // While a typing widget has focus the island waits for a click outside instead of a hover exit.
            // Holding the reveal modifier near the top opens the island even with hover-open off.
            let revealing = !presentation.isExpanded && ShellRevealPolicy.isRevealing(
                modifier: AppSettings.shared.shellRevealModifier, held: NSEvent.modifierFlags, pointer: pointer,
                zone: ShellRevealPolicy.zone(trigger: geometry.triggerFrame, screen: geometry.screenFrame))
            var effectiveTiming = timing
            if revealing { effectiveTiming.opensOnHover = true }
            hovering = surface.pinnedOpen || typing || tourHeld === presentation
                ? true : surface.hover.update(isInside: inside || revealing, isDragging: busy, now: now,
                                              timing: effectiveTiming)
        }
        holdNotification(inside && geometry.route == .notification && !presentation.isExpanded, on: surface)
        if presentation.isExpanded, presentation.expandedForNotification,
           NotificationHUDModel.shared.current == nil {
            close(surface)
            return
        }
        // Dragging files toward the notch opens it as a drop zone.
        let dragging = FileDragWatcher.shared.isDraggingFiles
        let dropHold = dragging && (geometry.dropZone.contains(pointer)
            || (presentation.isShowingDropTargets && geometry.containsPointer(pointer, expanded: true)))
        if dropHold != presentation.isShowingDropTargets && presentation.convertURLs.isEmpty {
            withAnimation(NotchMotion.layout(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                presentation.isShowingDropTargets = dropHold
            }
        }
        let expanded = announcing || hovering || dropHold || !presentation.convertURLs.isEmpty
        if expanded != presentation.isExpanded {
            // Opening from a bubble shows that bubble's activity (the song's opens the Music page).
            if expanded, let side = geometry.bubble(at: pointer, expanded: false),
               let activity = presentation.bubbleActivity(side) {
                presentation.showBubble(activity)
            }
            setExpanded(expanded, on: surface)
        }
        setAlpha(surface.visibility == .idle && !expanded ? 0 : 1, on: surface)
        focusTypingWidget(on: surface, expanded: expanded)
        let cardClickable = presentation.geometry.hudHovered
            && presentation.geometry.route.hudFlash?.action != nil
        surface.panel.ignoresMouseEvents = cardClickable ? !inside
            : (!expanded || !(geometry.containsPointer(pointer, expanded: true) || dropHold))
    }

    /// A typing widget (Termi-Notch, Notes, Calendar quick add…) is open and the island holds key focus.
    private func isTyping(on surface: Surface) -> Bool {
        surface.presentation.isExpanded && surface.panel.isKeyWindow
            && surface.presentation.navigation.openedWidget?.takesKeyboard == true
    }

    /// Terminal and prompter read keys without a text field, so the island takes focus when they open.
    private func focusTypingWidget(on surface: Surface, expanded: Bool) {
        let opened = expanded ? surface.presentation.navigation.openedWidget : nil
        guard opened != surface.focusedWidget else { return }
        surface.focusedWidget = opened
        guard let opened, opened.focusesOnOpen else { return }
        (surface.panel as? IslandPanel)?.keyAllowed = true
        surface.panel.makeKey()
    }

    /// The pointer on a HUD turns its strip into a card (on the shell's expansion spring) and keeps
    /// the flash up while it rests there, so a button such as Eject stays reachable.
    /// `shown` opens the card; `held` (the pointer resting on it) also keeps the flash from expiring.
    private func setHUDHover(_ shown: Bool, held: Bool, on surface: Surface) {
        let presentation = surface.presentation
        if surface.hudHeld != held {
            surface.hudHeld = held
            IslandFlashCenter.shared.setHeld(held)
        }
        guard presentation.geometry.hudHovered != shown else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(NotchMotion.expansion(shown, reduceMotion: reduce)) {
            presentation.geometry.hudHovered = shown
        }
    }

    /// Hovering a notification wing holds its dismiss timer; once open, the card manages the hold itself.
    private func holdNotification(_ hold: Bool, on surface: Surface) {
        guard surface.holdsNotification != hold else { return }
        surface.holdsNotification = hold
        NotificationHUDModel.shared.setPaused(hold)
    }

    private func observeMenus() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
                guard let menu = note.object as? NSMenu else { return }
                let identifier = ObjectIdentifier(menu)
                Task { @MainActor in
                    guard let self, self.surfaces.contains(where: { $0.presentation.isExpanded }) else { return }
                    self.trackingMenus.insert(identifier)
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
                guard let menu = note.object as? NSMenu else { return }
                let identifier = ObjectIdentifier(menu)
                Task { @MainActor in self?.trackingMenus.remove(identifier) }
            }
        ]
    }

    // MARK: - Island Tour

    /// The island the Island Tour teaches on: the display under the pointer when its island shows,
    /// else the first one showing. With `requireVisible` false it falls back to any display.
    func tourPresentation(requireVisible: Bool) -> NotchPresentation? {
        let pointer = NSEvent.mouseLocation
        let underPointer: (Surface) -> Bool = { $0.presentation.geometry.screenFrame.contains(pointer) }
        let shown = surfaces.filter { $0.visibility != .hidden }
        if let pick = shown.first(where: underPointer) ?? shown.first { return pick.presentation }
        guard !requireVisible else { return nil }
        return (surfaces.first(where: underPointer) ?? surfaces.first)?.presentation
    }

    /// The island on the display with this frame (the filmed demo targets the notched screen).
    func presentation(onScreen frame: CGRect) -> NotchPresentation? {
        surfaces.first { $0.presentation.geometry.screenFrame == frame }?.presentation
    }

    /// False once a display change rebuilt the islands and this one is gone.
    func hosts(_ presentation: NotchPresentation) -> Bool {
        surfaces.contains { $0.presentation === presentation }
    }

    /// The tour closes this island to show the closed island, or when it ends where it started closed.
    func collapseForTour(_ presentation: NotchPresentation) {
        guard let surface = surfaces.first(where: { $0.presentation === presentation }),
              surface.presentation.isExpanded else { return }
        close(surface)
    }

    /// Keeps the tour's island open the way its step needs; `.none` lets it close the usual way.
    func setTourHold(_ hold: IslandTourHold, on presentation: NotchPresentation?) {
        let released = [tourHeld, tourPinned].compactMap { $0 }
        tourHeld = hold == .open ? presentation : nil
        for surface in surfaces where released.contains(where: { $0 === surface.presentation }) {
            if surface.presentation === tourPinned { surface.pinnedOpen = false }
            // Released: it closes after the usual delay once the pointer is away, not at once.
            if surface.presentation.isExpanded { surface.hover.forceOpen() }
        }
        tourPinned = nil
        guard hold == .untilPointerLeaves,
              let surface = surfaces.first(where: { $0.presentation === presentation }),
              surface.presentation.isExpanded else { return }
        surface.hover.forceOpen()
        surface.pinnedOpen = true
        tourPinned = presentation
    }

    private func setExpanded(_ expanded: Bool, on surface: Surface) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        surface.transitionID += 1
        let transitionID = surface.transitionID
        let animation = NotchMotion.expansion(expanded, reduceMotion: reduceMotion)
        surface.summoned = expanded
        if expanded && !surface.presentation.isExpanded {
            ShellHaptics.tick()
            let p = surface.presentation
            // Only a plain hover opens onto the notification; the clipboard hotkey, convert and drops win.
            p.expandedForNotification = p.geometry.route == .notification && p.selectedActivity == nil
                && !p.isShowingLibrary && !p.isShowingActivities && !p.isShowingCalendar && p.convertURLs.isEmpty
            p.restorePage(surface.lastNavigation, closedOnMusic: p.geometry.route == .activity(.music))
        }
        (surface.panel as? IslandPanel)?.keyAllowed = expanded
        withAnimation(animation, completionCriteria: .removed) {
            surface.presentation.isExpanded = expanded
        } completion: {
            guard !expanded, !surface.presentation.isExpanded, surface.transitionID == transitionID else { return }
            surface.lastNavigation = surface.presentation.navigation
            // Closing the island ends Home's edit mode, keeping the changes (as leaving an iPhone
            // home screen does); otherwise the next hover would reopen it still jiggling.
            if !self.surfaces.contains(where: { $0.presentation.isExpanded }) { HomeWidgetStore.shared.isEditing = false }
            surface.presentation.selectedActivity = nil
            surface.presentation.homeTapped = false
            surface.presentation.isShowingLibrary = false
            surface.presentation.isShowingActivities = false
            surface.presentation.isShowingCalendar = false
            surface.presentation.isShowingMusic = false
            surface.presentation.isShowingMessages = false
            surface.presentation.isPresentingAudioOutputs = false
            surface.presentation.isShowingDropTargets = false
            surface.presentation.convertURLs = []
            surface.presentation.localSendURLs = []
            surface.presentation.expandedForNotification = false
        }
        surface.panel.ignoresMouseEvents = !expanded
            || !surface.presentation.geometry.containsPointer(NSEvent.mouseLocation, expanded: true)
        if !expanded, surface.panel.isKeyWindow { surface.panel.resignKey() }
    }
}
