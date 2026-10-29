import Combine
import Foundation
import Testing
@testable import Brim

@MainActor
struct CallDiscoveryTests {
    @Test("Unchanged unavailable discovery does not invalidate the notch")
    func unchangedUnavailableDiscoveryDoesNotPublish() throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let model = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { false }, scan: { _ in nil })
        model.refresh()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        model.refresh()
        #expect(publications == 0)
        withExtendedLifetime(subscription) {}
    }

    /// Walking an Electron app's accessibility tree (Discord, Slack) makes typing lag, so with no
    /// microphone in use there's no call to find and no other app is touched.
    @Test("Without an active microphone no app is scanned")
    func idleMicrophoneSkipsScanning() async throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let scans = ScanCounter()
        var microphone = false
        let model = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { true },
                                      microphoneInUse: { microphone },
                                      scan: { _ in scans.record(); return nil })
        model.refresh()
        try await Task.sleep(for: .milliseconds(60))
        #expect(scans.count == 0)
        #expect(model.activeCall == nil)
        microphone = true
        model.refresh()
        for _ in 0..<30 where scans.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(scans.count == 1)
        model.stop()
    }

    @Test("Unchanged idle discovery does not invalidate the notch")
    func unchangedIdleDiscoveryDoesNotPublish() async throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let scans = ScanCounter()
        let model = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { true },
                                      microphoneInUse: { true }, scan: { _ in scans.record(); return nil })
        model.refresh()
        for _ in 0..<100 where model.connectionStatus != "No active call detected. Calls appear here automatically." {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.connectionStatus == "No active call detected. Calls appear here automatically.")
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        model.refresh()
        for _ in 0..<100 where scans.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(scans.count == 2)
        #expect(publications == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test("Existing Accessibility permission allows automatic discovery without a Connect action")
    func trustedAppsAreDiscoveredAutomatically() async throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let scans = ScanCounter()
        var prompts = 0
        let model = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { true },
                                      requestPermission: { prompts += 1 }, microphoneInUse: { true },
                                      scan: { _ in scans.record(); return nil })
        model.refresh()
        for _ in 0..<30 where scans.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.isConnected)
        #expect(!model.needsAccessibilityPermission)
        #expect(scans.count == 1)
        #expect(prompts == 0)
        model.stop()
    }

    @Test("Missing Accessibility never prompts or scans automatically")
    func missingPermissionStaysQuietUntilExplicitAction() throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let scans = ScanCounter()
        var prompts = 0
        let model = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { false },
                                      requestPermission: { prompts += 1 }, microphoneInUse: { true },
                                      scan: { _ in scans.record(); return nil })
        model.refresh()
        model.refresh()
        #expect(model.needsAccessibilityPermission)
        #expect(!model.isConnected)
        #expect(prompts == 0)
        #expect(scans.count == 0)
        model.requestAccessibilityPermission()
        #expect(prompts == 1)
        #expect(scans.count == 0)
    }

    @Test("Explicitly pausing detection survives recreation and startup")
    func pausedDiscoveryDoesNotSilentlyResume() throws {
        let fixture = try CallDiscoveryFixture()
        defer { fixture.clean() }
        let first = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { true }, scan: { _ in nil })
        first.disconnect()
        let scans = ScanCounter()
        let reopened = CallActivityModel(settings: fixture.settings, accessibilityTrusted: { true },
                                         scan: { _ in scans.record(); return nil })
        reopened.start()
        defer { reopened.stop() }
        #expect(!reopened.isDetectionEnabled)
        #expect(!reopened.isConnected)
        #expect(scans.count == 0)
        #expect(!fixture.settings.callIntegrationEnabled)
    }
}

private struct CallDiscoveryFixture {
    let suite = "Brim.CallDiscoveryTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: AppSettings

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        settings = AppSettings(defaults: defaults)
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }
}

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}
