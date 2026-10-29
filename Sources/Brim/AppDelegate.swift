// AppDelegate.swift
// Brim
//
// Owns the menu-bar status item and wires together the app's top-level
// singletons on launch. Feature behavior lives behind the stub/contract
// types (CaptureCoordinator, HotkeyManager, SettingsWindowController, ...)
// so this file only needs to know about their public surface.

import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.terminateOthers()
        // A peer (the agent hook client, a LocalSend phone) closing its socket mid-write must
        // fail that write with EPIPE, not kill the whole app.
        signal(SIGPIPE, SIG_IGN)
        InputTrace.install()
        setupStatusItem()
        setupHotkey()
        applyDockVisibility()
        // Dragged-out images from a previous run (or a crash) shouldn't pile up in temp.
        DispatchQueue.global(qos: .utility).async { ImageDragExport.removeStale(in: ImageDragExport.folder) }
        if AppSettings.shared.notchShelfEnabled { NotchShelfController.shared.start() }
        // `--demo` only: scripted island states for filming (see DemoController).
        DemoController.shared.start()
        NowPlayingModel.shared.start()
        Task.detached(priority: .utility) { NowPlayingAccessibility.releaseChromeFullTree() }
        AudioOutputModel.shared.start()
        CallActivityModel.shared.start()
        ScreenRecordingModel.shared.start()
        NativeTimerModel.shared.start()
        ClipboardStore.shared.start()
        ActivityCenter.shared.start()
        FloatingBasketController.shared.start()
        TrackedFolders.shared.start()
        SystemSignalsMonitor.shared.start()
        startIslandFeatures()
        UpdateChecker.shared.startAutoCheck()

        NotificationCenterHelper.requestAuthorization()

        // Request capture access when the user starts a capture. Music and
        // calls remain usable without granting screen recording permission.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let senderPID = event?.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        let senderApp = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        guard ReopenPolicy.opensSettings(sender: senderApp) else {
            ReopenPolicy.log.notice("Ignored reopen from \(senderApp ?? "pid \(senderPID ?? 0)", privacy: .public)")
            return false
        }
        SettingsWindowController.shared.show()
        return true
    }

    /// Applies `AppSettings.showInDock` to the app's activation policy.
    /// Brim defaults to menu-bar-only (`.accessory`); opting in to
    /// `showInDock` switches to `.regular` so a Dock icon + app switcher
    /// entry appear.
    private func applyDockVisibility() {
        NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
    }

    /// Quitting (or logging out) mid-recording saves the recording first instead of discarding it,
    /// and lid-closed Stay Awake is turned off first so the Mac does not keep ignoring its lid.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let recording = RecordingController.shared.hasUnsavedRecording
        let lid = StayAwakeController.shared.lidClosedActive
        guard recording || lid else { return .terminateNow }
        var replied = false
        let quit = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        let releaseLid = { StayAwakeController.shared.releaseLidBeforeQuit(completion: quit) }
        if recording {
            RecordingController.shared.stop(openStudio: false, completion: releaseLid)
        } else {
            releaseLid()
        }
        // A writer or a password prompt that never finishes must not keep the Mac from logging out.
        DispatchQueue.main.asyncAfter(deadline: .now() + (lid ? 60 : 10), execute: quit)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DemoController.shared.stop()
        HotkeyManager.shared.unregister()
        HotkeyManager.shared.unregisterRing()
        NotchShelfController.shared.stop()
        NowPlayingModel.shared.stop()
        AudioOutputModel.shared.stop()
        CallActivityModel.shared.stop()
        ScreenRecordingModel.shared.stop()
        RecordingController.shared.shutdown()
        NativeTimerModel.shared.stop()
        ClipboardStore.shared.stop()
        ActivityCenter.shared.stop()
        FloatingBasketController.shared.stop()
        TrackedFolders.shared.stop()
        SystemSignalsMonitor.shared.stop()
        KeepAwakeModel.shared.stop(announce: false)
        ClipboardFeature.shared.stop()
        MediaServices.shared.stop()
        LiquidPlayerController.shared.stop()
        AudioControlModel.shared.stop()
        PreferredDeviceMonitor.shared.stop()
        IslandSpacebarMonitor.shared.stop()
        TermiNotchController.shared.stop()
        TeleprompterController.shared.stop()
        TextCaptureController.shared.stop()
        DropClipController.shared.stop()
        Droplets.shutdown()
    }

    /// Extra island features. Each one no-ops until its setting is on.
    private func startIslandFeatures() {
        ClipboardFeature.shared.start()
        HUDCoordinator.start()
        MediaServices.shared.start()
        LiquidPlayerController.shared.start()
        WeatherStore.shared.settingsChanged()
        StatsAlertMonitor.shared.settingsChanged()
        IslandGlanceModel.shared.start()
        NotificationHUDModel.shared.start()
        LockStatusRegistry.shared.register(WeatherLockStatusProvider())
        LockStatusRegistry.shared.register(SunLockStatusProvider())
        LockStatusRegistry.shared.register(AirQualityLockStatusProvider())
        SkyExtrasStore.shared.settingsChanged()
        LockScreenController.shared.start()
        RecordingResultModel.shared.start()
        RecordingController.shared.start()
        AudioControlModel.shared.start()
        if AppSettings.shared.preferredDevicesEnabled { PreferredDeviceMonitor.shared.start() }
        IslandSpacebarMonitor.shared.isIslandOpen = { NotchShelfController.shared.isAnyIslandOpen }
        IslandSpacebarMonitor.shared.start()
        AppIconController.applySaved()
        startDroplets()
    }

    /// Termi-Notch, Teleprompter, Text Capture, DropClip and the Droplets bundle (ring, emoji,
    /// Xcode builds, Stay Awake, LocalSend, MCP). Each no-ops until its setting is on.
    private func startDroplets() {
        TermiNotchController.shared.start()
        TeleprompterController.shared.start()
        TextCaptureController.shared.start()
        DropClipController.shared.start()
        NotesHotkeys.shared.start()
        TextCaptureModel.shared.onShowResult = { NotchShelfController.shared.presentWidget(.textCapture) }
        Droplets.start()
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppIconRenderer.menuBarGlyph()
        statusItem = item
        // The controller owns the icon's live status and click behavior (Command Center or this short menu).
        MenuBarController.shared.attach(item: item, shortMenu: buildMenu())
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let takeScreenshot = NSMenuItem(
            title: "Take Screenshot",
            action: #selector(takeScreenshotAction),
            keyEquivalent: "9"
        )
        takeScreenshot.keyEquivalentModifierMask = [.command, .shift]
        takeScreenshot.target = self
        menu.addItem(takeScreenshot)
        menu.addItem(RecordingController.shared.makeMenuItem())
        let openRecording = NSMenuItem(title: L10n.tr("Open Recording…"), action: #selector(openRecordingAction), keyEquivalent: "")
        openRecording.target = self
        menu.addItem(openRecording)

        let commandCenter = NSMenuItem(title: L10n.tr("Command Center…"), action: #selector(showCommandCenterAction), keyEquivalent: "")
        commandCenter.target = self
        menu.addItem(commandCenter)

        let shelf = NSMenuItem(title: L10n.tr("Notch Settings…"), action: #selector(showPreferencesAction), keyEquivalent: "")
        shelf.target = self
        menu.addItem(shelf)

        let islandTour = NSMenuItem(title: L10n.tr("Take the Island Tour"), action: #selector(islandTourAction), keyEquivalent: "")
        islandTour.target = self
        menu.addItem(islandTour)

        let screenshotHistory = NSMenuItem(
            title: "Screenshot History",
            action: #selector(showScreenshotHistoryAction),
            keyEquivalent: ""
        )
        screenshotHistory.target = self
        menu.addItem(screenshotHistory)

        let uploadHistory = NSMenuItem(
            title: "Upload History",
            action: #selector(showUploadHistoryAction),
            keyEquivalent: ""
        )
        uploadHistory.target = self
        menu.addItem(uploadHistory)

        menu.addItem(.separator())

        let preferences = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferencesAction),
            keyEquivalent: ","
        )
        preferences.keyEquivalentModifierMask = [.command]
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(.separator())

        let checkForUpdates = NSMenuItem(
            title: "Check for Updates",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        let quit = NSMenuItem(
            title: "Quit Brim",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        HotkeyManager.shared.onHotkey = {
            CaptureCoordinator.shared.startCapture()
        }
        HotkeyManager.shared.onRingHotkey = {
            RingMenuController.shared.toggle()
        }
        HotkeyManager.shared.register()
        HotkeyManager.shared.registerRing()
    }

    // MARK: - Menu actions

    @objc private func takeScreenshotAction() {
        CaptureCoordinator.shared.startCapture()
    }

    @objc private func openRecordingAction() {
        StudioWindowController.chooseProject()
    }

    @objc private func showCommandCenterAction() {
        CommandCenterController.shared.show(anchoredTo: statusItem?.button)
    }

    @objc private func showScreenshotHistoryAction() {
        HistoryWindowController.showHistoryWindow(kind: .save)
    }

    @objc private func showUploadHistoryAction() {
        HistoryWindowController.showHistoryWindow(kind: .upload)
    }

    @objc private func showPreferencesAction() {
        SettingsWindowController.shared.show()
    }

    @objc private func islandTourAction() {
        IslandTourController.shared.start()
    }

    @objc private func checkForUpdatesAction() {
        UpdateChecker.shared.checkInteractively()
    }
}

/// Which "reopen" requests open Settings. On macOS 27 the Siri app and its intelligence services
/// reopen running apps while you click around; only launchers the user drives should open Settings.
enum ReopenPolicy {
    static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "reopen")
    private static let userLaunchers: Set<String> = ["com.apple.dock", "com.apple.finder", "com.apple.Spotlight"]

    static func opensSettings(sender: String?) -> Bool {
        sender.map(userLaunchers.contains) ?? false
    }
}
