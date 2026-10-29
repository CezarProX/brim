import Combine
import CoreGraphics
import Darwin
import Foundation

struct ScreenRecordingActivity: Equatable, Sendable {
    let beganAt: Date
    /// Brim's own recorder (Recording/), not a detected system recording.
    var isInApp = false
    /// Elapsed seconds, frozen while Brim's recording is paused.
    var pausedElapsed: TimeInterval?
}

struct ScreenRecordingEvidence: Equatable, Sendable {
    let identity: String
}

enum ScreenRecordingStopError: Error, Equatable, LocalizedError {
    case noActiveRecording
    case recordingChanged
    case accessibilityPermissionRequired
    case couldNotCreateShortcut

    var errorDescription: String? {
        switch self {
        case .noActiveRecording, .recordingChanged:
            "The screen recording is no longer active."
        case .accessibilityPermissionRequired:
            "Allow Brim to control your Mac in System Settings > Privacy & Security > Accessibility, then try again."
        case .couldNotCreateShortcut:
            "Brim could not send the macOS stop-recording shortcut."
        }
    }
}

/// Observes native Screenshot recordings, including QuickTime's New Screen Recording flow.
/// macOS has no public system-wide recording notification: this deliberately does not infer
/// recording from an open toolbar, a privacy permission, or an unrelated app's capture session.
@MainActor
final class ScreenRecordingModel: ObservableObject {
    static let shared = ScreenRecordingModel()
    @Published private(set) var activeRecording: ScreenRecordingActivity?
    @Published private(set) var isWorking = false
    @Published private(set) var stopError: String?

    private let probe: @Sendable () async -> ScreenRecordingEvidence?
    private let stopAction: @Sendable (ScreenRecordingEvidence) async throws -> Void
    private let now: () -> Date
    private var polling: Task<Void, Never>?
    private var generation = 0
    private var isRefreshing = false
    private var identity: String?
    private var stopRequestID: UUID?
    /// While Brim's own recorder runs it owns the activity, Stop and Pause.
    private var inApp: InAppHandlers?

    struct InAppHandlers {
        let stop: @MainActor () -> Void
        let togglePause: @MainActor () -> Void
    }

    var supportsPause: Bool { inApp != nil }

    init(probe: @escaping @Sendable () async -> ScreenRecordingEvidence? = {
        await Task.detached(priority: .utility) { NativeScreenRecordingProbe.scan() }.value
    }, stopAction: @escaping @Sendable (ScreenRecordingEvidence) async throws -> Void = { expected in
        try await Task.detached(priority: .userInitiated) {
            try NativeScreenRecordingStopBridge().stop(expected: expected)
        }.value
    }, now: @escaping () -> Date = Date.init) {
        self.probe = probe
        self.stopAction = stopAction
        self.now = now
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

    /// Stops observing; it never stops another application's recording.
    func stop() {
        generation += 1
        polling?.cancel()
        polling = nil
        identity = nil
        stopRequestID = nil
        isWorking = false
        stopError = nil
        if activeRecording != nil { activeRecording = nil }
    }

    func showInAppRecording(_ activity: ScreenRecordingActivity, handlers: InAppHandlers) {
        inApp = handlers
        stopError = nil
        isWorking = false
        if activeRecording != activity { activeRecording = activity }
    }

    func endInAppRecording() {
        guard inApp != nil else { return }
        inApp = nil
        isWorking = false
        activeRecording = nil
    }

    func togglePause() { inApp?.togglePause() }

    func stopRecording() async {
        guard !isWorking else { return }
        if let inApp {
            isWorking = true
            inApp.stop()
            return
        }
        guard let identity, activeRecording != nil else {
            stopError = ScreenRecordingStopError.noActiveRecording.localizedDescription
            return
        }
        let expected = ScreenRecordingEvidence(identity: identity)
        let requestGeneration = generation
        let requestID = UUID()
        stopRequestID = requestID
        isWorking = true
        stopError = nil
        defer {
            if stopRequestID == requestID {
                stopRequestID = nil
                isWorking = false
            }
        }
        do {
            try await stopAction(expected)
            guard requestGeneration == generation, self.identity == expected.identity else { return }
            await refreshNow()
        } catch {
            guard requestGeneration == generation, self.identity == expected.identity else { return }
            stopError = error.localizedDescription
        }
    }

    func refreshNow() async {
        guard !isRefreshing, inApp == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let currentGeneration = generation
        let evidence = await probe()
        guard currentGeneration == generation, !Task.isCancelled, inApp == nil else { return }
        guard let evidence else {
            identity = nil
            stopError = nil
            if activeRecording != nil { activeRecording = nil }
            return
        }
        guard identity != evidence.identity else { return }
        identity = evidence.identity
        stopError = nil
        // Elapsed time is measured from first observation, including recordings already underway.
        activeRecording = ScreenRecordingActivity(beganAt: now())
    }

    deinit { polling?.cancel() }
}

/// Uses Apple's documented Command-Control-Escape stop shortcut. The recording is
/// revalidated immediately before posting so an old notch action cannot stop a newer session.
struct NativeScreenRecordingStopBridge {
    private let currentEvidence: () -> ScreenRecordingEvidence?
    private let hasPostEventAccess: () -> Bool
    private let postShortcut: () throws -> Void

    init(
        currentEvidence: @escaping () -> ScreenRecordingEvidence? = { NativeScreenRecordingProbe.scan() },
        hasPostEventAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        postShortcut: @escaping () throws -> Void = { try Self.postCommandControlEscape() }
    ) {
        self.currentEvidence = currentEvidence
        self.hasPostEventAccess = hasPostEventAccess
        self.postShortcut = postShortcut
    }

    func stop(expected: ScreenRecordingEvidence) throws {
        guard currentEvidence() == expected else { throw ScreenRecordingStopError.recordingChanged }
        guard hasPostEventAccess() else { throw ScreenRecordingStopError.accessibilityPermissionRequired }
        try postShortcut()
    }

    private static func postCommandControlEscape() throws {
        let escapeKey: CGKeyCode = 0x35
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: escapeKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: escapeKey, keyDown: false) else {
            throw ScreenRecordingStopError.couldNotCreateShortcut
        }
        let flags: CGEventFlags = [.maskCommand, .maskControl]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/// Reads descriptor metadata only. No video content, Accessibility access, shell processes,
/// Screen Recording permission requests, or file-system scans are involved.
enum NativeScreenRecordingProbe {
    private static let maxProcesses = 4_096
    private static let maxDescriptors = 2_048
    private static let recorderExecutables: Set<String> = [
        "/usr/sbin/screencapture",
        "/usr/libexec/replayd",
        "/System/Applications/Utilities/Screenshot.app/Contents/MacOS/Screenshot",
        "/System/Applications/Utilities/Screenshot.app/Contents/PlugIns/ScreenshotControls.appex/Contents/MacOS/ScreenshotControls"
    ]

    static func isRecorderExecutable(_ path: String) -> Bool {
        recorderExecutables.contains(path)
    }

    static func scan() -> ScreenRecordingEvidence? {
        var pids = [pid_t](repeating: 0, count: maxProcesses)
        let size = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, size)
        guard bytes > 0 else { return nil }
        let count = min(Int(bytes) / MemoryLayout<pid_t>.stride, pids.count)
        for pid in pids.prefix(count) where pid > 0 {
            var executable = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &executable, UInt32(executable.count)) > 0,
                  isRecorderExecutable(String(cString: executable)) else { continue }
            // Recent macOS versions delegate writing to replayd, which also serves other apps.
            // Only its native Screenshot storage directory is evidence of a screen recording.
            let requiresNativePath = String(cString: executable) == "/usr/libexec/replayd"
            if let evidence = recordingEvidence(pid: pid, requiresNativePath: requiresNativePath) { return evidence }
        }
        return nil
    }

    static func isNativeRecordingPath(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        return directory == home.appendingPathComponent("Library/Group Containers/group.com.apple.screencapture/ScreenRecordings", isDirectory: true)
            || directory == home.appendingPathComponent("Library/ScreenRecordings", isDirectory: true)
    }

    static func recordingEvidence(pid: pid_t, requiresNativePath: Bool = false) -> ScreenRecordingEvidence? {
        // Bound every scan even if a process rapidly opens descriptors or exits mid-query.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: maxDescriptors)
        let size = Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard bytes > 0 else { return nil }
        let count = min(Int(bytes) / MemoryLayout<proc_fdinfo>.stride, descriptors.count)
        for descriptor in descriptors.prefix(count) where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
            var info = vnode_fdinfowithpath()
            let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, infoSize) == infoSize,
                  info.pfi.fi_openflags & UInt32(FWRITE) != 0 else { continue }
            let stat = info.pvip.vip_vi.vi_stat
            guard stat.vst_mode & UInt16(S_IFMT) == UInt16(S_IFREG) else { continue }
            let moviePath = withUnsafeBytes(of: &info.pvip.vip_path) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard (moviePath as NSString).pathExtension.lowercased() == "mov",
                  !requiresNativePath || isNativeRecordingPath(moviePath) else { continue }
            return ScreenRecordingEvidence(identity: "\(pid):\(stat.vst_dev):\(stat.vst_ino)")
        }
        return nil
    }
}
