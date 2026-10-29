import AppKit
import ApplicationServices
import Combine
import Foundation

struct NativeTimerActivity: Equatable, Sendable {
    let id: String
    let title: String
    let duration: TimeInterval
    let endDate: Date?
    let pausedRemaining: TimeInterval?

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, min(duration, pausedRemaining ?? endDate?.timeIntervalSince(date) ?? 0))
    }
}

/// Observes actual macOS Clock timers even while Clock's window is closed.
/// Observation never creates, cancels, or changes a native timer.
@MainActor
final class NativeTimerModel: ObservableObject {
    static let shared = NativeTimerModel()
    @Published private(set) var activeTimer: NativeTimerActivity?
    @Published private(set) var isWorking = false
    @Published private(set) var controlError: String?
    @Published private(set) var controlCapability: NativeTimerControlCapability

    private let probe: @Sendable () async -> NativeTimerActivity?
    private let accessibilityTrusted: () -> Bool
    private let control: @Sendable (NativeTimerAction, NativeTimerActivity) async -> NativeTimerControlResult
    private var polling: Task<Void, Never>?
    private var generation = 0
    private var isRefreshing = false

    init(probe: @escaping @Sendable () async -> NativeTimerActivity? = {
             await Task.detached(priority: .utility) { NativeTimerProbe.scan() }.value
         },
         accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         control: @escaping @Sendable (NativeTimerAction, NativeTimerActivity) async -> NativeTimerControlResult = {
             await NativeTimerControls.perform($0, expected: $1)
         }) {
        self.probe = probe
        self.accessibilityTrusted = accessibilityTrusted
        self.control = control
        controlCapability = accessibilityTrusted() ? .available : .accessibilityPermissionRequired
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                do { try await Task.sleep(for: .milliseconds(750)) }
                catch { return }
            }
        }
    }

    func stop() {
        generation += 1
        polling?.cancel()
        polling = nil
        activeTimer = nil
        isWorking = false
        controlError = nil
    }

    func refreshNow() async {
        updateCapability()
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let currentGeneration = generation
        let snapshot = await probe()
        guard generation == currentGeneration, !Task.isCancelled else { return }
        if activeTimer?.id != snapshot?.id {
            if controlError != nil { controlError = nil }
            controlCapability = accessibilityTrusted() ? .available : .accessibilityPermissionRequired
        }
        if activeTimer != snapshot { activeTimer = snapshot }
    }

    func pause(expectedID: String) async { await perform(.pause, expectedID: expectedID) }
    func resume(expectedID: String) async { await perform(.resume, expectedID: expectedID) }
    func cancel(expectedID: String) async { await perform(.cancel, expectedID: expectedID) }

    /// Called only from the explicit permission button in the timer UI.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        updateCapability()
    }

    private func perform(_ action: NativeTimerAction, expectedID: String) async {
        guard !isWorking, let timer = activeTimer, timer.id == expectedID,
              isValid(action, for: timer) else {
            controlError = "This timer changed before the action could run."
            return
        }
        updateCapability()
        guard accessibilityTrusted() else {
            controlError = "Allow Brim in Accessibility settings to control Clock."
            return
        }
        if controlCapability != .available { controlCapability = .available }
        isWorking = true
        controlError = nil
        let currentGeneration = generation
        let result = await control(action, timer)
        guard generation == currentGeneration else { return }
        isWorking = false
        switch result {
        case .success:
            await refreshNow()
        case .accessibilityPermissionRequired:
            controlCapability = .accessibilityPermissionRequired
            controlError = "Allow Brim in Accessibility settings to control Clock."
        case .staleTimer:
            controlError = "This timer changed before the action could run."
            await refreshNow()
        case let .unavailable(message):
            controlCapability = .unavailable(message)
            controlError = message
        case let .failed(message):
            controlError = message
        }
    }

    private func isValid(_ action: NativeTimerAction, for timer: NativeTimerActivity) -> Bool {
        switch action {
        case .pause: return !timer.isPaused
        case .resume: return timer.isPaused
        case .cancel: return true
        }
    }

    private func updateCapability() {
        if !accessibilityTrusted() {
            if controlCapability != .accessibilityPermissionRequired {
                controlCapability = .accessibilityPermissionRequired
            }
        } else if controlCapability == .accessibilityPermissionRequired {
            controlCapability = .available
        }
    }

    deinit { polling?.cancel() }
}
