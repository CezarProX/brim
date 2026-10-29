import AppKit
import ApplicationServices
import Combine

@MainActor
final class CallActivityModel: ObservableObject {
    static let shared = CallActivityModel()
    @Published private(set) var activeCall: CallActivity?
    @Published private(set) var connectionStatus = "Looking for active calls…"
    @Published private(set) var isConnected = false
    @Published private(set) var isDetectionEnabled: Bool
    @Published private(set) var needsAccessibilityPermission: Bool
    @Published private(set) var canToggleMute = false
    @Published private(set) var canToggleCamera = false
    @Published private(set) var canToggleScreenShare = false
    @Published private(set) var canLeave = false
    @Published private(set) var isWorking = false

    private let worker = DispatchQueue(label: "io.github.cezarprox.brim.call-accessibility", qos: .utility)
    private var timer: Timer?
    private var snapshot: CallSnapshot?
    private var generation = 0
    private var isPolling = false
    private let authorization = CallAuthorizationGate()
    private let settings: AppSettings
    private let accessibilityTrusted: () -> Bool
    private let requestPermission: () -> Void
    private let scan: @Sendable ([CallProcess]) -> CallSnapshot?
    private let microphoneInUse: () -> Bool

    init(settings: AppSettings = .shared,
         accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         requestPermission: (() -> Void)? = nil,
         microphoneInUse: @escaping () -> Bool = { SystemSignalsMonitor.microphoneRunning() },
         scan: @escaping @Sendable ([CallProcess]) -> CallSnapshot? = { CallAccessibilityBridge.scan($0) }) {
        self.microphoneInUse = microphoneInUse
        self.settings = settings
        self.accessibilityTrusted = accessibilityTrusted
        self.requestPermission = requestPermission ?? Self.requestSystemPermission
        self.scan = scan
        isDetectionEnabled = settings.callIntegrationEnabled
        needsAccessibilityPermission = !accessibilityTrusted()
        updateAvailability()
    }

    func start() {
        guard timer == nil else { return }
        if settings.callIntegrationEnabled { authorization.renew() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        MeetingHotkey.shared.register(settings: settings)
    }

    func stop() {
        MeetingHotkey.shared.unregister()
        authorization.invalidate()
        generation += 1
        timer?.invalidate()
        timer = nil
        clear()
        isConnected = false
    }

    func enableDetection() {
        settings.callIntegrationEnabled = true
        authorization.renew()
        start()
        refresh()
    }

    /// Only this explicit UI action asks macOS for Accessibility permission.
    func requestAccessibilityPermission() {
        guard !accessibilityTrusted() else { refresh(); return }
        requestPermission()
        refresh()
    }

    func disconnect() {
        authorization.invalidate()
        settings.callIntegrationEnabled = false
        generation += 1
        clear()
        isConnected = false
        isDetectionEnabled = false
        connectionStatus = "Automatic call detection is paused."
    }

    func refresh() {
        MicrophoneMuteController.shared.refresh()
        updateAvailability()
        guard isDetectionEnabled, !needsAccessibilityPermission else {
            authorization.invalidate()
            generation += 1
            clear()
            return
        }
        if authorization.currentToken() == nil { authorization.renew() }
        // Every call needs the microphone. Without one, don't touch other apps: walking an Electron
        // app's accessibility tree (Discord, Slack, Teams) every few seconds makes typing lag.
        guard microphoneInUse() else {
            generation += 1
            isPolling = false
            accept(nil)
            return
        }
        guard !isWorking, !isPolling else { return }
        isPolling = true
        let currentGeneration = generation
        let processes = candidateProcesses()
        let scan = scan
        worker.async { [weak self] in
            let result = scan(processes)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPolling = false
                guard self.generation == currentGeneration, self.settings.callIntegrationEnabled,
                      self.accessibilityTrusted() else { return }
                self.accept(result)
            }
        }
    }

    func openCall() {
        guard let snapshot else { return }
        NSRunningApplication(processIdentifier: snapshot.process.pid)?.activate()
    }

    func toggleMute() { perform(.mute) }
    func toggleCamera() { perform(.camera) }
    func toggleScreenShare(expectedID: UUID) {
        guard activeCall?.id == expectedID else { return }
        perform(.screenShare)
    }
    func leave(expectedID: UUID) {
        guard activeCall?.id == expectedID else { return }
        perform(.leave)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateAvailability() {
        let enabled = settings.callIntegrationEnabled
        let needsPermission = !accessibilityTrusted()
        let connected = enabled && !needsPermission
        if isDetectionEnabled != enabled { isDetectionEnabled = enabled }
        if needsAccessibilityPermission != needsPermission { needsAccessibilityPermission = needsPermission }
        if isConnected != connected { isConnected = connected }
        let nextStatus: String
        if !enabled { nextStatus = "Automatic call detection is paused." }
        else if needsPermission {
            nextStatus = "Allow Accessibility once to show calls automatically."
        } else if activeCall == nil {
            // Keep a completed idle scan's status stable while the next background scan runs.
            nextStatus = connectionStatus == "No active call detected. Calls appear here automatically."
                ? connectionStatus : "Watching for active calls automatically."
        } else { nextStatus = connectionStatus }
        if connectionStatus != nextStatus { connectionStatus = nextStatus }
    }

    private static func requestSystemPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func candidateProcesses() -> [CallProcess] {
        let preferredPID = snapshot?.process.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard let id = application.bundleIdentifier else { return nil }
            if let app = CallApp(bundleIdentifier: id) {
                return CallProcess(pid: application.processIdentifier, app: app, isBrowser: false)
            }
            if CallAccessibilityBridge.browserIDs.contains(id) {
                return CallProcess(pid: application.processIdentifier, app: .googleMeet, isBrowser: true)
            }
            return nil
        }.sorted { $0.pid == preferredPID && $1.pid != preferredPID }
    }

    private func accept(_ result: CallSnapshot?) {
        guard let result else {
            clear()
            let status = "No active call detected. Calls appear here automatically."
            if connectionStatus != status { connectionStatus = status }
            return
        }
        let sameCall = snapshot.map {
            $0.process.pid == result.process.pid && CFEqual($0.window, result.window)
                && CFEqual($0.scope, result.scope) && $0.title == result.title
        } ?? false
        let beganAt = sameCall ? activeCall?.beganAt ?? Date() : Date()
        let identity = sameCall ? activeCall?.id ?? UUID() : UUID()
        snapshot = result
        let call = CallActivity(id: identity, processIdentifier: result.process.pid,
                                appName: result.process.app.name, title: result.title,
                                beganAt: beganAt, isMuted: result.evidence.isMuted,
                                isCameraOn: result.evidence.isCameraOn,
                                isScreenSharing: result.evidence.isScreenSharing)
        if activeCall != call { activeCall = call }
        if !canToggleMute { canToggleMute = true }
        let app = result.process.app
        let fallback = settings.meetingShortcutFallbackEnabled
        let hasCamera = result.evidence.cameraLabel != nil || (fallback && MeetingShortcutMap.chord(.camera, for: app) != nil)
        if canToggleCamera != hasCamera { canToggleCamera = hasCamera }
        let hasScreenShare = result.evidence.screenShareLabel != nil
            || (fallback && MeetingShortcutMap.chord(.share, for: app) != nil)
        if canToggleScreenShare != hasScreenShare { canToggleScreenShare = hasScreenShare }
        if !canLeave { canLeave = true }
        if connectionStatus != "Connected" { connectionStatus = "Connected" }
    }

    private func perform(_ action: CallAction) {
        guard let snapshot, !isWorking, settings.callIntegrationEnabled, accessibilityTrusted(),
              let token = authorization.currentToken() else { return }
        isWorking = true
        let currentGeneration = generation
        let authorization = self.authorization
        worker.async { [weak self] in
            let success = CallAccessibilityBridge.perform(action, snapshot: snapshot, authorization: authorization, token: token)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isWorking = false
                guard self.generation == currentGeneration else { return }
                if !success, self.settings.callIntegrationEnabled, authorization.currentToken() == token,
                   self.sendShortcut(for: action, snapshot: snapshot) {
                    self.refresh()
                } else if !success {
                    self.clear()
                    self.connectionStatus = "Call controls changed. Open the call app to continue."
                } else {
                    self.refresh()
                }
            }
        }
    }

    /// Falls back to the call app's own keyboard shortcut when its control couldn't be pressed.
    private func sendShortcut(for action: CallAction, snapshot: CallSnapshot) -> Bool {
        guard settings.meetingShortcutFallbackEnabled, accessibilityTrusted(),
              let meeting = MeetingShortcutMap.action(for: action),
              let chord = MeetingShortcutMap.chord(meeting, for: snapshot.process.app) else { return false }
        let pid = snapshot.process.pid
        if MeetingShortcutMap.requiresFrontmost(snapshot.process.app),
           NSWorkspace.shared.frontmostApplication?.processIdentifier != pid { return false }
        return MeetingShortcutSender.send(chord, toPID: pid)
    }

    /// Mutes or unmutes every microphone on this Mac, independent of the call app.
    func toggleSystemMute() { MicrophoneMuteController.shared.toggle() }

    private func clear() {
        snapshot = nil
        if activeCall != nil { activeCall = nil }
        if canToggleMute { canToggleMute = false }
        if canToggleCamera { canToggleCamera = false }
        if canToggleScreenShare { canToggleScreenShare = false }
        if canLeave { canLeave = false }
    }
}
