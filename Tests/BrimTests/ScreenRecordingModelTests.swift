import Darwin
import Foundation
import Testing
@testable import Brim

private actor RecordingProbeStub {
    var evidence: ScreenRecordingEvidence?
    var pending: CheckedContinuation<ScreenRecordingEvidence?, Never>?
    var suspend = false
    var reads = 0
    func read() async -> ScreenRecordingEvidence? {
        reads += 1
        if suspend {
            suspend = false
            return await withCheckedContinuation { pending = $0 }
        }
        return evidence
    }
    func set(_ identity: String?) { evidence = identity.map { ScreenRecordingEvidence(identity: $0) } }
    func suspendNext() { suspend = true }
    var isWaiting: Bool { pending != nil }
    func finish() { pending?.resume(returning: ScreenRecordingEvidence(identity: "late")); pending = nil }
}

private actor RecordingStopStub {
    var received: [ScreenRecordingEvidence] = []
    var error: (any Error)?
    var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func perform(_ evidence: ScreenRecordingEvidence) async throws {
        received.append(evidence)
        if suspended {
            await withCheckedContinuation { continuation = $0 }
        }
        if let error { throw error }
    }

    func suspend() { suspended = true }
    func release() { continuation?.resume(); continuation = nil }
    var callCount: Int { received.count }
}

private actor RecordingStopRaceGate {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var callCount = 0

    func perform(_ evidence: ScreenRecordingEvidence) async {
        callCount += 1
        let call = callCount
        await withCheckedContinuation { continuations[call] = $0 }
    }

    func release(_ call: Int) {
        continuations.removeValue(forKey: call)?.resume()
    }
}

@MainActor
struct ScreenRecordingModelTests {
    @Test func initializationIsPassiveAndStartDoesNotDuplicatePolling() async {
        let probe = RecordingProbeStub()
        let model = ScreenRecordingModel(probe: { await probe.read() })
        #expect(await probe.reads == 0)
        await probe.suspendNext()
        model.start()
        model.start()
        for _ in 0..<1_000 where !(await probe.isWaiting) { await Task.yield() }
        #expect(await probe.isWaiting)
        #expect(await probe.reads == 1)
        model.stop()
        await probe.finish()
        #expect(model.activeRecording == nil)
    }

    @Test func recordingTransitionsPreserveStartUntilRecordingChanges() async {
        let probe = RecordingProbeStub()
        var now = Date(timeIntervalSince1970: 100)
        let model = ScreenRecordingModel(probe: { await probe.read() }, now: { now })
        await model.refreshNow()
        #expect(model.activeRecording == nil)
        await probe.set("first")
        await model.refreshNow()
        #expect(model.activeRecording?.beganAt == now)
        now = Date(timeIntervalSince1970: 120)
        await model.refreshNow()
        #expect(model.activeRecording?.beganAt == Date(timeIntervalSince1970: 100))
        await probe.set("second")
        await model.refreshNow()
        #expect(model.activeRecording?.beganAt == now)
        await probe.set(nil)
        await model.refreshNow()
        #expect(model.activeRecording == nil)
    }

    @Test func stopDiscardsInflightDetection() async {
        let probe = RecordingProbeStub()
        await probe.suspendNext()
        let model = ScreenRecordingModel(probe: { await probe.read() })
        let refresh = Task { await model.refreshNow() }
        for _ in 0..<1_000 where !(await probe.isWaiting) { await Task.yield() }
        #expect(await probe.isWaiting)
        model.stop()
        await probe.finish()
        await refresh.value
        #expect(model.activeRecording == nil)
    }

    @Test func onlyAppleScreenRecorderExecutablesAreCandidates() {
        #expect(NativeScreenRecordingProbe.isRecorderExecutable("/usr/sbin/screencapture"))
        #expect(NativeScreenRecordingProbe.isRecorderExecutable("/usr/libexec/replayd"))
        #expect(NativeScreenRecordingProbe.isRecorderExecutable("/System/Applications/Utilities/Screenshot.app/Contents/PlugIns/ScreenshotControls.appex/Contents/MacOS/ScreenshotControls"))
        #expect(!NativeScreenRecordingProbe.isRecorderExecutable("/tmp/screencapture"))
        #expect(!NativeScreenRecordingProbe.isRecorderExecutable("/System/Applications/QuickTime Player.app/Contents/MacOS/QuickTime Player"))
    }

    @Test func replayDaemonEvidenceMustBelongToNativeScreenshotStorage() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(NativeScreenRecordingProbe.isNativeRecordingPath(home + "/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/recording.mov"))
        #expect(NativeScreenRecordingProbe.isNativeRecordingPath(home + "/Library/ScreenRecordings/recording.mov"))
        #expect(!NativeScreenRecordingProbe.isNativeRecordingPath(home + "/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings-other/recording.mov"))
        #expect(!NativeScreenRecordingProbe.isNativeRecordingPath(home + "/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/../other.mov"))
        #expect(!NativeScreenRecordingProbe.isNativeRecordingPath("/tmp/recording.mov"))
    }

    @Test func descriptorEvidenceRequiresWritableMovieAndDisappearsWhenClosed() throws {
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let descriptor = open(movie.path, O_CREAT | O_RDWR | O_EXCL, S_IRUSR | S_IWUSR)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { try? FileManager.default.removeItem(at: movie) }
        let evidence = NativeScreenRecordingProbe.recordingEvidence(pid: getpid())
        #expect(evidence != nil)
        #expect(NativeScreenRecordingProbe.recordingEvidence(pid: getpid(), requiresNativePath: true) == nil)
        close(descriptor)
        #expect(NativeScreenRecordingProbe.recordingEvidence(pid: getpid()) != evidence)
        let readOnly = open(movie.path, O_RDONLY)
        #expect(readOnly >= 0)
        defer { if readOnly >= 0 { close(readOnly) } }
        #expect(NativeScreenRecordingProbe.recordingEvidence(pid: getpid()) != evidence)
    }

    @Test func stopRecordingRequiresCurrentEvidenceAndForwardsItsExactIdentity() async {
        let probe = RecordingProbeStub()
        let stop = RecordingStopStub()
        let model = ScreenRecordingModel(
            probe: { await probe.read() },
            stopAction: { try await stop.perform($0) }
        )

        await model.stopRecording()
        #expect(await stop.callCount == 0)
        #expect(model.stopError == "The screen recording is no longer active.")

        await probe.set("native-recording")
        await model.refreshNow()
        await model.stopRecording()
        #expect(await stop.received == [ScreenRecordingEvidence(identity: "native-recording")])
        #expect(model.stopError == nil)
        #expect(!model.isWorking)
    }

    @Test func stopRecordingPreventsDuplicateRequestsAndSurfacesFailure() async {
        let probe = RecordingProbeStub()
        let stop = RecordingStopStub()
        await probe.set("native-recording")
        await stop.suspend()
        let model = ScreenRecordingModel(
            probe: { await probe.read() },
            stopAction: { try await stop.perform($0) }
        )
        await model.refreshNow()

        let first = Task { await model.stopRecording() }
        for _ in 0..<1_000 where await stop.callCount == 0 { await Task.yield() }
        #expect(model.isWorking)
        await model.stopRecording()
        #expect(await stop.callCount == 1)
        await stop.release()
        await first.value
        #expect(!model.isWorking)

        let failing = ScreenRecordingModel(
            probe: { ScreenRecordingEvidence(identity: "native-recording") },
            stopAction: { _ in throw ScreenRecordingStopError.accessibilityPermissionRequired }
        )
        await failing.refreshNow()
        await failing.stopRecording()
        #expect(failing.stopError == "Allow Brim to control your Mac in System Settings > Privacy & Security > Accessibility, then try again.")
    }

    @Test func nativeStopBridgeRejectsStaleRecordingBeforePostingShortcut() throws {
        var posted = false
        let stale = NativeScreenRecordingStopBridge(
            currentEvidence: { ScreenRecordingEvidence(identity: "replacement") },
            hasPostEventAccess: { true },
            postShortcut: { posted = true }
        )
        #expect(throws: ScreenRecordingStopError.recordingChanged) {
            try stale.stop(expected: ScreenRecordingEvidence(identity: "original"))
        }
        #expect(!posted)

        let denied = NativeScreenRecordingStopBridge(
            currentEvidence: { ScreenRecordingEvidence(identity: "original") },
            hasPostEventAccess: { false },
            postShortcut: { posted = true }
        )
        #expect(throws: ScreenRecordingStopError.accessibilityPermissionRequired) {
            try denied.stop(expected: ScreenRecordingEvidence(identity: "original"))
        }
        #expect(!posted)
    }

    @Test func staleStopCompletionCannotClearNewRecordingAction() async {
        let probe = RecordingProbeStub()
        let gate = RecordingStopRaceGate()
        await probe.set("first")
        let model = ScreenRecordingModel(
            probe: { await probe.read() },
            stopAction: { await gate.perform($0) }
        )
        await model.refreshNow()
        let first = Task { await model.stopRecording() }
        for _ in 0..<1_000 where await gate.callCount < 1 { await Task.yield() }

        model.stop()
        await probe.set("second")
        await model.refreshNow()
        let second = Task { await model.stopRecording() }
        for _ in 0..<1_000 where await gate.callCount < 2 { await Task.yield() }
        #expect(model.isWorking)

        await gate.release(1)
        await first.value
        #expect(model.isWorking)
        await gate.release(2)
        await second.value
        #expect(!model.isWorking)
    }
}
