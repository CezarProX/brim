import Combine
import CoreAudio
import Foundation
import Testing
@testable import Brim

private actor StubAudioOutputProvider: AudioOutputProviding {
    var current: AudioOutputSnapshot
    var selections: [UInt32] = []
    var reads = 0
    var readFails = false
    var selectionFails = false
    var pendingRead: CheckedContinuation<AudioOutputSnapshot, Never>?
    var shouldSuspendRead = false

    init(_ snapshot: AudioOutputSnapshot) { current = snapshot }

    func snapshot() async throws -> AudioOutputSnapshot {
        reads += 1
        if readFails { throw StubError.unavailable }
        if shouldSuspendRead {
            shouldSuspendRead = false
            return await withCheckedContinuation { pendingRead = $0 }
        }
        return current
    }

    func select(_ id: UInt32) async throws -> AudioOutputSnapshot {
        selections.append(id)
        guard !selectionFails, current.devices.contains(where: { $0.id == id }) else {
            throw StubError.unavailable
        }
        current = AudioOutputSnapshot(devices: current.devices, selectedID: id)
        return current
    }

    func suspendNextRead() { shouldSuspendRead = true }
    var hasPendingRead: Bool { pendingRead != nil }
    func finishRead(_ snapshot: AudioOutputSnapshot) {
        pendingRead?.resume(returning: snapshot)
        pendingRead = nil
    }

    func failReads() { readFails = true }
    func failSelection() { selectionFails = true }
    func replace(_ snapshot: AudioOutputSnapshot) { current = snapshot }

    private enum StubError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Audio device unavailable" }
    }
}

@MainActor
struct AudioOutputModelTests {
    private let builtIn = AudioOutputDevice(id: 1, name: "MacBook Speakers", icon: "speaker.wave.2.fill")
    private let headphones = AudioOutputDevice(id: 2, name: "Connected Headphones", icon: "headphones")

    @Test func initializationDoesNotProbeOrChangeSystemOutput() async {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn], selectedID: 1))
        let model = AudioOutputModel(provider: provider)
        #expect(model.devices.isEmpty)
        #expect(model.selectedID == nil)
        #expect(await provider.reads == 0)
        #expect(await provider.selections.isEmpty)
    }

    @Test func explicitSelectionDisplaysVerifiedProviderRoute() async {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1))
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await model.selectNow(headphones)
        #expect(await provider.selections == [2])
        #expect(model.selectedID == 2)
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
    }

    @Test func missingDeviceIsNotOptimisticallySelected() async {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1))
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await provider.replace(AudioOutputSnapshot(devices: [builtIn], selectedID: 1))
        await model.selectNow(headphones)
        #expect(model.devices == [builtIn])
        #expect(model.selectedID == 1)
        #expect(model.errorMessage != nil)
        await model.selectNow(headphones)
        #expect(await provider.selections == [2])
    }

    @Test func failedSelectionReadsActualRouteAndExposesError() async {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1))
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await provider.failSelection()
        await model.selectNow(headphones)
        #expect(model.selectedID == 1)
        #expect(model.errorMessage == "Audio device unavailable")
        #expect(!model.isBusy)
    }

    @Test func failedRefreshClearsStaleDeviceList() async {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn], selectedID: 1))
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await provider.failReads()
        await model.refreshNow()
        #expect(model.devices.isEmpty)
        #expect(model.selectedID == nil)
        #expect(model.errorMessage != nil)
        #expect(await provider.selections.isEmpty)
    }
    @Test func monitoringUpdatesExternalRoutesAndStops() async throws {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1))
        let model = AudioOutputModel(provider: provider, pollingInterval: .milliseconds(10))
        model.start()
        model.start()
        defer { model.stop() }
        for _ in 0..<100 where model.selectedID != 1 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.selectedDevice == builtIn)
        await provider.replace(AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 2))
        for _ in 0..<100 where model.selectedID != 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.selectedDevice == headphones)
        #expect(await provider.selections.isEmpty)
        model.stop()
        let stoppedReads = await provider.reads
        await provider.replace(AudioOutputSnapshot(devices: [builtIn], selectedID: 1))
        try await Task.sleep(for: .milliseconds(40))
        #expect(await provider.reads == stoppedReads)
        #expect(model.selectedDevice == headphones)
        model.start()
        for _ in 0..<100 where model.selectedID != 1 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.selectedDevice == builtIn)
    }

    @Test func unchangedBackgroundSnapshotsDoNotPublishOrShowBusy() async throws {
        let provider = StubAudioOutputProvider(AudioOutputSnapshot(devices: [builtIn], selectedID: 1))
        let model = AudioOutputModel(provider: provider, pollingInterval: .milliseconds(10))
        await model.refreshNow()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        model.start()
        defer { model.stop(); subscription.cancel() }
        // Wait for a second background read: the previous poll has then applied its
        // result, even when concurrent render tests occupy the main actor.
        for _ in 0..<200 {
            if await provider.reads >= 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.reads >= 3)
        #expect(publications == 0)
        #expect(!model.isBusy)
    }

    @Test func airPodsIconsUseNameAndModelIdentity() {
        #expect(CoreAudioOutputProvider.icon(name: "Alex’s AirPods Pro", modelUID: nil, transport: nil) == "airpodspro")
        #expect(CoreAudioOutputProvider.icon(name: "AirPods Max", modelUID: nil, transport: nil) == "airpodsmax")
        #expect(CoreAudioOutputProvider.icon(name: "AirPods", modelUID: nil, transport: nil) == "airpods")
        #expect(CoreAudioOutputProvider.icon(name: "My earbuds", modelUID: "AirPodsPro", transport: nil) == "airpodspro")
        #expect(CoreAudioOutputProvider.icon(name: "Other headphones", modelUID: nil, transport: kAudioDeviceTransportTypeBluetooth) == "headphones")
        #expect(CoreAudioOutputProvider.icon(name: "Monitor", modelUID: nil, transport: kAudioDeviceTransportTypeHDMI) == "display")
    }

    @Test func stoppedMonitorDiscardsInFlightRead() async throws {
        let oldRoute = AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1)
        let provider = StubAudioOutputProvider(oldRoute)
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await provider.suspendNextRead()
        model.start()
        for _ in 0..<100 {
            if await provider.hasPendingRead { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await provider.hasPendingRead)
        model.stop()
        await provider.finishRead(AudioOutputSnapshot(devices: [headphones], selectedID: 2))
        try await Task.sleep(for: .milliseconds(10))
        #expect(model.selectedDevice == builtIn)
    }

    @Test func oldBackgroundReadCannotOverwriteCompletedSelection() async throws {
        let oldRoute = AudioOutputSnapshot(devices: [builtIn, headphones], selectedID: 1)
        let provider = StubAudioOutputProvider(oldRoute)
        let model = AudioOutputModel(provider: provider)
        await model.refreshNow()
        await provider.suspendNextRead()
        model.start()
        defer { model.stop() }
        for _ in 0..<100 {
            if await provider.hasPendingRead { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await provider.hasPendingRead)
        await model.selectNow(headphones)
        await provider.finishRead(oldRoute)
        try await Task.sleep(for: .milliseconds(10))
        #expect(model.selectedDevice == headphones)
    }

}
