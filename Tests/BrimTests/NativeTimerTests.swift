import Foundation
import SQLite3
import Testing
@testable import Brim

struct NativeTimerTests {
    private func archive(_ root: [String: Any], date: TimeInterval? = nil) throws -> Data {
        var objects: [Any] = ["$null", root]
        if let date { objects.append(["NS.time": date]) }
        return try PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$objects": objects], format: .binary, options: 0)
    }

    @Test func runningTimerCountsDownAndExpires() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let data = try archive(["MTTimerTimeDate": 2], date: now.addingTimeInterval(60).timeIntervalSinceReferenceDate)
        let timer = try #require(NativeTimerProbe.decode(id: "test", title: "Tea", duration: 120, state: 3, fireTime: data))
        #expect(timer.remaining(at: now) == 60)
        #expect(timer.remaining(at: now.addingTimeInterval(70)) == 0)
        #expect(!timer.isPaused)
    }

    @Test func pausedTimerDoesNotCountDown() throws {
        let data = try archive(["MTTimerTimeInterval": 43.5])
        let timer = try #require(NativeTimerProbe.decode(id: "test", title: "", duration: 120, state: 2, fireTime: data))
        #expect(timer.title == "Timer")
        #expect(timer.isPaused)
        #expect(timer.remaining(at: .distantPast) == 43.5)
        #expect(timer.remaining(at: .distantFuture) == 43.5)
    }

    @Test func rejectsInactiveMalformedAndNonfiniteTimers() throws {
        let data = try archive(["MTTimerTimeInterval": 43.5])
        for state in [0, 1, 4, 5] {
            #expect(NativeTimerProbe.decode(id: "a", title: "", duration: 120, state: state, fireTime: data) == nil)
        }
        #expect(NativeTimerProbe.decode(id: "a", title: "", duration: .infinity, state: 2, fireTime: data) == nil)
        #expect(NativeTimerProbe.decode(id: "a", title: "", duration: 120, state: 3, fireTime: data) == nil)
        #expect(NativeTimerProbe.decode(id: "a", title: "", duration: 120, state: 2, fireTime: Data()) == nil)
        let negative = try archive(["MTTimerTimeInterval": -1])
        #expect(NativeTimerProbe.decode(id: "a", title: "", duration: 120, state: 2, fireTime: negative) == nil)
    }

    @Test @MainActor func observationUpdatesPauseResumeAndStop() async {
        let running = NativeTimerActivity(id: "a", title: "Tea", duration: 60, endDate: Date().addingTimeInterval(60), pausedRemaining: nil)
        let model = NativeTimerModel(probe: { running })
        await model.refreshNow()
        #expect(model.activeTimer == running)
        model.stop()
        #expect(model.activeTimer == nil)
    }

    @Test func sqliteProbeUsesActualRunningStateAndRemainsReadOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("timers.sqlite")
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let soon = try archive(["MTTimerTimeDate": 2], date: now.addingTimeInterval(30).timeIntervalSinceReferenceDate)
        let later = try archive(["MTTimerTimeDate": 2], date: now.addingTimeInterval(90).timeIntervalSinceReferenceDate)
        let paused = try archive(["MTTimerTimeInterval": 10.0])
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "CREATE TABLE ZMTCDTIMER (ZMTID BLOB, ZTITLE TEXT, ZDURATION REAL, ZSTATE INTEGER, ZFIRETIME BLOB, ZLASTMODIFIEDDATE REAL)", nil, nil, nil) == SQLITE_OK)
        for (id, state, data) in [("01", 3, later), ("02", 3, soon), ("03", 2, paused)] {
            let hex = data.map { String(format: "%02x", $0) }.joined()
            let query = "INSERT INTO ZMTCDTIMER VALUES (X'\(id)', 'Tea', 120, \(state), X'\(hex)', 0)"
            #expect(sqlite3_exec(database, query, nil, nil, nil) == SQLITE_OK)
        }
        let original = try Data(contentsOf: url)
        #expect(NativeTimerProbe.scanAll(url: url, now: now).count == 3)
        #expect(NativeTimerProbe.scan(url: url, now: now)?.id == "02")
        #expect(NativeTimerProbe.scan(url: url, now: now.addingTimeInterval(40))?.id == "01")
        #expect(NativeTimerProbe.scan(url: url, now: now.addingTimeInterval(100))?.id == "03")
        #expect(try Data(contentsOf: url) == original)
        let missing = directory.appendingPathComponent("missing.sqlite")
        #expect(NativeTimerProbe.scan(url: missing, now: now) == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test @MainActor func stopDiscardsAnInFlightObservation() async throws {
        let timer = NativeTimerActivity(id: "a", title: "Tea", duration: 60, endDate: nil, pausedRemaining: 30)
        let gate = NativeTimerTestGate()
        let model = NativeTimerModel(probe: {
            await gate.waitForRelease()
            return timer
        })
        let refresh = Task { await model.refreshNow() }
        await gate.waitUntilStarted()
        model.stop()
        await gate.release()
        await refresh.value
        #expect(model.activeTimer == nil)
    }

    @Test @MainActor func pauseUsesTheDisplayedTimerIdentity() async throws {
        let timer = NativeTimerActivity(id: "expected", title: "Tea", duration: 60,
                                        endDate: Date().addingTimeInterval(45), pausedRemaining: nil)
        let actions = NativeTimerActionRecorder(result: .success)
        let model = NativeTimerModel(probe: { timer }, accessibilityTrusted: { true },
                                     control: { action, expected in
                                         await actions.record(action, expected: expected)
                                     })
        await model.refreshNow()
        await model.pause(expectedID: timer.id)
        let invocation = try #require(await actions.last)
        #expect(invocation.action == .pause)
        #expect(invocation.timer.id == timer.id)
        #expect(!model.isWorking)
        #expect(model.controlError == nil)
        #expect(model.controlCapability == .available)
    }

    @Test @MainActor func staleOrInvalidActionsNeverReachClock() async {
        let running = NativeTimerActivity(id: "current", title: "Tea", duration: 60,
                                          endDate: Date().addingTimeInterval(45), pausedRemaining: nil)
        let actions = NativeTimerActionRecorder(result: .success)
        let model = NativeTimerModel(probe: { running }, accessibilityTrusted: { true },
                                     control: { action, expected in
                                         await actions.record(action, expected: expected)
                                     })
        await model.refreshNow()
        await model.pause(expectedID: "replaced")
        await model.resume(expectedID: running.id)
        #expect(await actions.count == 0)
        #expect(model.controlError == "This timer changed before the action could run.")
    }

    @Test @MainActor func permissionAndBridgeFailuresArePublished() async {
        let paused = NativeTimerActivity(id: "paused", title: "Tea", duration: 60,
                                         endDate: nil, pausedRemaining: 30)
        let denied = NativeTimerModel(probe: { paused }, accessibilityTrusted: { false },
                                      control: { _, _ in .success })
        await denied.refreshNow()
        await denied.resume(expectedID: paused.id)
        #expect(denied.controlCapability == .accessibilityPermissionRequired)
        #expect(denied.controlError == "Allow Brim in Accessibility settings to control Clock.")

        let failed = NativeTimerModel(probe: { paused }, accessibilityTrusted: { true },
                                      control: { _, _ in .failed("Clock did not expose the expected timer control.") })
        await failed.refreshNow()
        await failed.cancel(expectedID: paused.id)
        #expect(failed.controlCapability == .available)
        #expect(failed.controlError == "Clock did not expose the expected timer control.")
    }

    @Test func nativeControlAdapterRejectsIdentityStateAndTimeMismatches() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let running = NativeTimerActivity(id: "a", title: "Tea", duration: 60,
                                          endDate: now.addingTimeInterval(30), pausedRemaining: nil)
        let replacement = NativeTimerActivity(id: "b", title: "Tea", duration: 60,
                                              endDate: now.addingTimeInterval(30), pausedRemaining: nil)
        let paused = NativeTimerActivity(id: "a", title: "Tea", duration: 60,
                                         endDate: nil, pausedRemaining: 30)
        #expect(NativeTimerControls.matchesFresh(expected: running, fresh: running, action: .pause))
        #expect(!NativeTimerControls.matchesFresh(expected: running, fresh: replacement, action: .pause))
        #expect(!NativeTimerControls.matchesFresh(expected: running, fresh: paused, action: .pause))
        #expect(NativeTimerControls.uniqueFresh(expected: running, candidates: [running], action: .pause) == running)
        #expect(NativeTimerControls.uniqueFresh(expected: running, candidates: [running, replacement], action: .pause) == nil)
        #expect(NativeTimerControlEvidence(title: "Tea", remaining: 28).matches(running, now: now, tolerance: 2))
        #expect(!NativeTimerControlEvidence(title: "Coffee", remaining: 30).matches(running, now: now, tolerance: 2))
        #expect(!NativeTimerControlEvidence(title: "Tea", remaining: 20).matches(running, now: now, tolerance: 2))
    }

    @Test @MainActor func capabilityRefreshesAfterPermissionAndErrorsClearForANewTimer() async {
        var trusted = false
        let first = NativeTimerActivity(id: "first", title: "Tea", duration: 60,
                                        endDate: nil, pausedRemaining: 30)
        let second = NativeTimerActivity(id: "second", title: "Coffee", duration: 90,
                                         endDate: nil, pausedRemaining: 45)
        let probe = NativeTimerValueProbe(first)
        let model = NativeTimerModel(probe: { await probe.read() }, accessibilityTrusted: { trusted },
                                     control: { _, _ in .failed("Fixture failure") })
        await model.refreshNow()
        #expect(model.controlCapability == .accessibilityPermissionRequired)
        trusted = true
        await model.refreshNow()
        #expect(model.controlCapability == .available)
        await model.cancel(expectedID: first.id)
        #expect(model.controlError == "Fixture failure")
        await probe.set(second)
        await model.refreshNow()
        #expect(model.activeTimer?.id == second.id)
        #expect(model.controlError == nil)
    }

}

private actor NativeTimerActionRecorder {
    struct Invocation: Sendable {
        let action: NativeTimerAction
        let timer: NativeTimerActivity
    }

    let result: NativeTimerControlResult
    private(set) var invocations: [Invocation] = []
    var last: Invocation? { invocations.last }
    var count: Int { invocations.count }

    init(result: NativeTimerControlResult) { self.result = result }

    func record(_ action: NativeTimerAction, expected: NativeTimerActivity) -> NativeTimerControlResult {
        invocations.append(Invocation(action: action, timer: expected))
        return result
    }
}

private actor NativeTimerValueProbe {
    private var value: NativeTimerActivity?

    init(_ value: NativeTimerActivity?) { self.value = value }
    func read() -> NativeTimerActivity? { value }
    func set(_ value: NativeTimerActivity?) { self.value = value }
}


private actor NativeTimerTestGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
