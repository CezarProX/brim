// RecordingController.swift
// Brim
//
// The recorder's state machine: bar → (area pick) → countdown → recording ⇄ paused → saving →
// Studio. Entry points: the menu-bar item, the Command Center tile, the hotkey (default ⌃⇧5,
// toggles start/stop) and the island's Stop / Pause buttons.

import AppKit
import AVFoundation
import os

@MainActor
final class RecordingController: NSObject, ObservableObject {
    static let shared = RecordingController()
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "recording")

    enum Phase: Equatable { case idle, choosing, preparing, countdown, recording, paused, saving }

    @Published private(set) var phase: Phase = .idle

    private let settings: AppSettings
    private let bar = RecordingBarPanel()
    private let countdown = RecordingCountdown()
    private let pointer = CursorTrackRecorder()
    private let hotkey = DropletHotkey()
    private var barModel: RecordingBarModel?
    private var session: Session?

    private struct Session {
        let recorder: ScreenRecorder
        let target: ResolvedRecordingTarget
        let project: RecordingProject
        let options: ScreenRecorder.Options
        let createdAt: Date
        var activeSince: Date
        var elapsedBeforePause: TimeInterval = 0
    }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
    }

    var isRecording: Bool { phase == .recording || phase == .paused }
    /// Callers waiting for a save already in progress (quitting while it finishes).
    private var savingCompletions: [() -> Void] = []
    /// A recording is running or still being written to disk.
    var hasUnsavedRecording: Bool { isRecording || phase == .saving }

    // MARK: Lifecycle

    func start() { registerHotkey() }

    func registerHotkey() {
        hotkey.onPress = { [weak self] in self?.toggle() }
        let binding = settings.recordScreenShortcut
        if binding.isSet { hotkey.register(keyCode: binding.keyCode, modifiers: binding.modifiers) } else { hotkey.unregister() }
    }

    /// Called when the app quits. A recording in progress was already saved by
    /// `AppDelegate.applicationShouldTerminate`; anything still half-written is dropped.
    func shutdown() {
        hotkey.unregister()
        guard let session else { return }
        _ = pointer.stop()
        let recorder = session.recorder
        Task { await recorder.cancel() }
    }

    /// Hotkey / menu / tile: open the recorder, or stop the current recording.
    func toggle() {
        switch phase {
        case .idle: showBar()
        case .choosing: closeBar()
        case .countdown: countdown.close()
        case .recording, .paused: stop()
        case .preparing, .saving: break
        }
    }

    func showBar() {
        guard phase == .idle || phase == .choosing else { return }
        let model = RecordingBarModel(settings: settings)
        model.onClose = { [weak self] in self?.closeBar() }
        model.onRecord = { [weak self, weak model] in
            guard let self, let model else { return }
            self.begin(kind: model.kind, windowID: model.windowID)
        }
        barModel = model
        bar.show(model: model)
        phase = .choosing
    }

    private func closeBar() {
        bar.close()
        barModel = nil
        if phase == .choosing { phase = .idle }
    }

    // MARK: Starting

    private func begin(kind: RecordingSourceKind, windowID: CGWindowID?) {
        bar.close()
        phase = .preparing
        Task {
            switch kind {
            case .display: await prepare(.display(RecordingSourceResolver.displayUnderPointer()))
            case .window:
                guard let windowID else { return finishWithoutRecording() }
                await prepare(.window(windowID))
            case .area: await pickArea()
            }
        }
    }

    private func pickArea() async {
        do {
            let frozen = try await ScreenCapturer.captureFullScreens()
            RecordingAreaPicker.shared.pick(frozen: frozen) { [weak self] result in
                guard let self else { return }
                guard let (display, rect) = result else { return self.finishWithoutRecording() }
                Task { await self.prepare(.area(display, rect)) }
            }
        } catch {
            report(error)
        }
    }

    private func prepare(_ target: RecordingTarget) async {
        var options = ScreenRecorder.Options(fps: settings.recordingFPS, systemAudio: settings.recordingSystemAudio,
                                             microphone: settings.recordingMicrophone)
        if options.microphone, !(await Self.microphoneAllowed()) {
            options.microphone = false
            IslandFlashCenter.shared.show(L10n.tr("Microphone access is not allowed, so this recording will not include narration."),
                                          symbol: "mic.slash.fill", tint: .orange)
        }
        do {
            let resolved = try await RecordingSourceResolver.resolve(target, retina: settings.recordingRetina)
            let project = try RecordingProject.create(in: RecordingLibrary.root)
            let recorder = try ScreenRecorder(target: resolved, options: options, outputURL: project.videoURL)
            let screen = NSScreen.screens.first { screen in
                screen.recordingDisplayID.map { CGDisplayBounds($0).intersects(resolved.captureRect) } ?? false
            }
            phase = .countdown
            guard await countdown.run(seconds: settings.recordingCountdown, on: screen) else {
                await recorder.cancel()
                try? FileManager.default.removeItem(at: project.folder)
                return finishWithoutRecording()
            }
            pointer.start()
            try await recorder.start()
            recorder.onStreamStopped = { error in
                Task { @MainActor in
                    RecordingController.log.error("Stream stopped: \(error.localizedDescription, privacy: .public)")
                    RecordingController.shared.stop()
                }
            }
            let now = Date()
            session = Session(recorder: recorder, target: resolved, project: project, options: options, createdAt: now, activeSince: now)
            phase = .recording
            publishActivity()
        } catch {
            _ = pointer.stop()
            report(error)
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Pause / stop

    func togglePause() {
        guard var session else { return }
        if phase == .recording {
            session.recorder.pause()
            session.elapsedBeforePause += Date().timeIntervalSince(session.activeSince)
            phase = .paused
        } else if phase == .paused {
            session.recorder.resume()
            session.activeSince = Date()
            phase = .recording
        }
        self.session = session
        publishActivity()
    }

    /// Ends the recording and saves it. `openStudio` false (quitting) saves without opening the
    /// editor; `completion` runs once the file is safe or the save failed.
    func stop(openStudio: Bool = true, completion: (() -> Void)? = nil) {
        if phase == .saving {
            // Already being written; wait for that save rather than cancelling it.
            savingCompletions.append { completion?() }
            return
        }
        guard let session, isRecording else { completion?(); return }
        phase = .saving
        let events = pointer.stop()
        Task {
            do {
                let (duration, clock) = try await session.recorder.stop()
                let track = CursorTrackBuilder.build(events: events, clock: clock, captureRect: session.target.captureRect)
                let metadata = RecordingMetadata(
                    id: UUID(), createdAt: session.createdAt, title: RecordingLibrary.title(for: session.createdAt),
                    source: session.target.kind, pixelWidth: Int(session.target.pixelSize.width),
                    pixelHeight: Int(session.target.pixelSize.height), pointWidth: session.target.pointSize.width,
                    pointHeight: session.target.pointSize.height, fps: session.options.fps, duration: duration,
                    hasSystemAudio: session.options.systemAudio, hasMicrophone: session.options.microphone)
                try session.project.save(metadata)
                try? session.project.save(track)
                let edit = StudioEdit.initial(duration: duration, track: track, style: settings.studioDefaultStyle)
                try? session.project.save(edit)
                self.session = nil
                phase = .idle
                ScreenRecordingModel.shared.endInAppRecording()
                if openStudio { StudioWindowController.open(project: session.project) }
            } catch {
                self.session = nil
                ScreenRecordingModel.shared.endInAppRecording()
                report(error, title: L10n.tr("Couldn't save the recording"))
            }
            completion?()
            let waiting = savingCompletions
            savingCompletions = []
            waiting.forEach { $0() }
        }
    }

    private func publishActivity() {
        guard let session else { return }
        let elapsed = session.elapsedBeforePause + (phase == .paused ? 0 : Date().timeIntervalSince(session.activeSince))
        let activity = ScreenRecordingActivity(beganAt: Date().addingTimeInterval(-elapsed), isInApp: true,
                                               pausedElapsed: phase == .paused ? elapsed : nil)
        ScreenRecordingModel.shared.showInAppRecording(activity, handlers: .init(
            stop: { RecordingController.shared.stop() },
            togglePause: { RecordingController.shared.togglePause() }))
    }

    private func finishWithoutRecording() {
        phase = .idle
        barModel = nil
    }

    private func report(_ error: Error, title: String = L10n.tr("Couldn't start the recording")) {
        phase = .idle
        session = nil
        ScreenRecordingModel.shared.endInAppRecording()
        if case ScreenCapturer.CaptureError.permissionDenied = error {
            PermissionsHelper.showScreenRecordingRecovery()
            return
        }
        Self.log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        IslandFlashCenter.shared.show(title, symbol: "exclamationmark.triangle.fill", tint: .red)
        NotificationCenterHelper.notify(title: title, body: error.localizedDescription)
    }

    // MARK: Menu

    /// The status menu's "Record Screen" / "Stop Recording" item.
    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.tr("Record Screen"), action: #selector(menuAction), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuAction() { toggle() }
}

extension RecordingController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(menuAction) else { return true }
        menuItem.title = isRecording ? L10n.tr("Stop Recording") : L10n.tr("Record Screen")
        let binding = settings.recordScreenShortcut
        menuItem.keyEquivalent = ""
        menuItem.toolTip = binding.isSet ? binding.display : nil
        return phase != .saving && phase != .preparing
    }
}
