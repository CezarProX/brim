import AppKit
import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    let icon: String
}

struct AudioOutputSnapshot: Equatable, Sendable {
    let devices: [AudioOutputDevice]
    let selectedID: UInt32?
}

protocol AudioOutputProviding: Sendable {
    func snapshot() async throws -> AudioOutputSnapshot
    func select(_ id: UInt32) async throws -> AudioOutputSnapshot
}

@MainActor
final class AudioOutputModel: ObservableObject {
    static let shared = AudioOutputModel()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var selectedID: UInt32?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false

    var selectedDevice: AudioOutputDevice? { devices.first { $0.id == selectedID } }

    private let provider: any AudioOutputProviding
    private let pollingInterval: Duration
    private var monitoringTask: Task<Void, Never>?
    private var explicitRequestGeneration = 0

    init(
        provider: any AudioOutputProviding = CoreAudioOutputProvider(),
        pollingInterval: Duration = .seconds(1)
    ) {
        self.provider = provider
        self.pollingInterval = max(pollingInterval, .milliseconds(10))
    }

    deinit { monitoringTask?.cancel() }

    /// Keep the route current even when the picker has never been opened.
    func start() {
        guard monitoringTask == nil else { return }
        let interval = pollingInterval
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshInBackground()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func refreshInBackground() async {
        guard !isBusy, !Task.isCancelled else { return }
        let generation = explicitRequestGeneration
        do {
            let current = try await provider.snapshot()
            // An explicit selection can begin while the provider read is suspended.
            guard !Task.isCancelled, !isBusy, generation == explicitRequestGeneration else { return }
            apply(current)
        } catch {
            // Preserve the last verified route during temporary Bluetooth handoffs.
            // Explicit picker refreshes still surface read failures to the user.
        }
    }

    func refresh() {
        Task { await refreshNow() }
    }

    func select(_ device: AudioOutputDevice) {
        Task { await selectNow(device) }
    }

    func refreshNow() async {
        guard !isBusy else { return }
        explicitRequestGeneration &+= 1
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            apply(try await provider.snapshot())
        } catch {
            devices = []
            selectedID = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectNow(_ device: AudioOutputDevice) async {
        guard !isBusy, devices.contains(device) else { return }
        explicitRequestGeneration &+= 1
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            apply(try await provider.select(device.id))
        } catch {
            // A device may disappear or another app may change the route during the request.
            // Read back reality instead of optimistically marking the requested device selected.
            if let current = try? await provider.snapshot() {
                apply(current)
            } else {
                devices = []
                selectedID = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ snapshot: AudioOutputSnapshot) {
        if devices != snapshot.devices { devices = snapshot.devices }
        if selectedID != snapshot.selectedID { selectedID = snapshot.selectedID }
    }
}

/// CoreAudio runs on this actor, never on the main actor. Only an explicit select changes routing.
actor CoreAudioOutputProvider: AudioOutputProviding {
    func snapshot() throws -> AudioOutputSnapshot {
        let devices = try outputDevices()
        let current = try uintProperty(
            object: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        return AudioOutputSnapshot(
            devices: devices,
            selectedID: devices.contains(where: { $0.id == current }) ? current : nil
        )
    }

    func select(_ id: UInt32) throws -> AudioOutputSnapshot {
        // Revalidate on the serial actor immediately before changing the default output.
        guard try outputDevices().contains(where: { $0.id == id }) else {
            throw AudioOutputError.unavailable
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(system, &address, &settable), action: "check audio output")
        guard settable.boolValue else { throw AudioOutputError.readOnly }
        var selected = id
        try check(
            AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &selected),
            action: "switch audio output"
        )
        let result = try snapshot()
        guard result.selectedID == id else { throw AudioOutputError.notSelected }
        return result
    }

    private func outputDevices() throws -> [AudioOutputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = property(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount), action: "read audio devices")
        guard byteCount <= 16_384, byteCount % UInt32(MemoryLayout<AudioObjectID>.stride) == 0 else {
            throw AudioOutputError.invalidData
        }
        guard byteCount > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioObjectID>.stride)
        let capacity = byteCount
        let status = ids.withUnsafeMutableBytes { storage in
            AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, storage.baseAddress!)
        }
        try check(status, action: "read audio devices")
        guard byteCount <= capacity, byteCount % UInt32(MemoryLayout<AudioObjectID>.stride) == 0 else {
            throw AudioOutputError.invalidData
        }
        var seen = Set<AudioObjectID>()
        return ids.prefix(Int(byteCount) / MemoryLayout<AudioObjectID>.stride).compactMap { id in
            guard id != kAudioObjectUnknown, seen.insert(id).inserted,
                  (try? uintProperty(object: id, selector: kAudioDevicePropertyDeviceIsAlive)) == 1,
                  (try? uintProperty(object: id, selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                     scope: kAudioObjectPropertyScopeOutput)) == 1,
                  (try? hasOutputChannels(id)) == true,
                  let name = try? deviceName(id), !name.isEmpty else { return nil }
            let transport = try? uintProperty(object: id, selector: kAudioDevicePropertyTransportType)
            let modelUID = try? stringProperty(id, selector: kAudioDevicePropertyModelUID)
            return AudioOutputDevice(id: id, name: name, icon: Self.icon(name: name, modelUID: modelUID, transport: transport))
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func hasOutputChannels(_ id: AudioObjectID) throws -> Bool {
        var address = property(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &byteCount), action: "read output channels")
        let headerSize = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size
        guard byteCount >= headerSize, byteCount <= 65_536 else { throw AudioOutputError.invalidData }
        let capacity = Int(byteCount)
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: max(capacity, MemoryLayout<AudioBufferList>.size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, storage), action: "read output channels")
        guard byteCount >= headerSize, byteCount <= capacity else { throw AudioOutputError.invalidData }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let available = (Int(byteCount) - headerSize) / MemoryLayout<AudioBuffer>.stride
        guard list.pointee.mNumberBuffers <= available else { throw AudioOutputError.invalidData }
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private func deviceName(_ id: AudioObjectID) throws -> String {
        try stringProperty(id, selector: kAudioObjectPropertyName)
    }

    private func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = property(selector)
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, &value), action: "read device name")
        guard let value else { throw AudioOutputError.invalidData }
        return (value.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uintProperty(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> UInt32 {
        var address = property(selector, scope: scope)
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &byteCount, &value), action: "read audio output")
        guard byteCount == MemoryLayout<UInt32>.size else { throw AudioOutputError.invalidData }
        return value
    }

    private func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, action: String) throws {
        guard status == noErr else { throw AudioOutputError.system(action, status) }
    }

    private static let supportedAirPodsSymbols: Set<String> = Set(
        ["airpods", "airpodspro", "airpodsmax"].filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    )

    nonisolated static func icon(name: String, modelUID: String?, transport: UInt32?) -> String {
        let identity = (name + " " + (modelUID ?? "")).lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let airPodsSymbol: String?
        if identity.contains("airpodsmax") { airPodsSymbol = "airpodsmax" }
        else if identity.contains("airpodspro") { airPodsSymbol = "airpodspro" }
        else if identity.contains("airpods") { airPodsSymbol = "airpods" }
        else { airPodsSymbol = nil }
        if let airPodsSymbol {
            return supportedAirPodsSymbols.contains(airPodsSymbol) ? airPodsSymbol : "headphones"
        }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        default: return "speaker.wave.2.fill"
        }
    }
}

private enum AudioOutputError: LocalizedError {
    case unavailable, readOnly, invalidData, notSelected
    case system(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "This audio device is no longer available."
        case .readOnly: return "macOS cannot change the current audio output."
        case .invalidData: return "macOS returned incomplete audio device information."
        case .notSelected: return "The audio output did not change. Try selecting the device again."
        case let .system(action, status): return "Could not \(action) (macOS error \(status))."
        }
    }
}
