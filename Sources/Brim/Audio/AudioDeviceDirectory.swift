import CoreAudio
import Foundation

struct AudioDeviceRef: Identifiable, Equatable, Hashable, Sendable {
  let id: UInt32
  /// Persistent identifier: survives reboots, unlike `id`.
  let uid: String
  let name: String
  let isOutput: Bool
  let isInput: Bool
  let isAirPlay: Bool
  let isBluetooth: Bool
  let isAggregate: Bool
}

protocol AudioDeviceListing: Sendable {
  func devices() -> [AudioDeviceRef]
  func defaultDevice(input: Bool) -> AudioDeviceRef?
  @discardableResult func setDefault(_ device: AudioDeviceRef, input: Bool) -> Bool
}

/// Core Audio devices with uid and direction. Private aggregates (our own taps) are hidden.
struct CoreAudioDeviceDirectory: AudioDeviceListing {
  func devices() -> [AudioDeviceRef] {
    CoreAudioProperty.objectIDs(CoreAudioProperty.system, kAudioHardwarePropertyDevices).compactMap(ref(for:))
  }

  func defaultDevice(input: Bool) -> AudioDeviceRef? {
    let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    guard let id = CoreAudioProperty.uint32(CoreAudioProperty.system, selector), id != kAudioObjectUnknown else { return nil }
    return ref(for: id)
  }

  @discardableResult
  func setDefault(_ device: AudioDeviceRef, input: Bool) -> Bool {
    var addr = CoreAudioProperty.address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    var value = device.id
    return AudioObjectSetPropertyData(CoreAudioProperty.system, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
  }

  private func ref(for id: AudioObjectID) -> AudioDeviceRef? {
    guard let uid = CoreAudioProperty.string(id, kAudioDevicePropertyDeviceUID),
          let name = CoreAudioProperty.string(id, kAudioObjectPropertyName), !name.isEmpty else { return nil }
    let transport = CoreAudioProperty.uint32(id, kAudioDevicePropertyTransportType) ?? 0
        if uid.hasPrefix("Brim") { return nil }
    return AudioDeviceRef(
      id: id, uid: uid, name: name,
      isOutput: channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
      isInput: channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
      isAirPlay: transport == kAudioDeviceTransportTypeAirPlay,
      isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
      isAggregate: transport == kAudioDeviceTransportTypeAggregate)
  }

  private func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var addr = CoreAudioProperty.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size >= 8, size <= 65_536 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
  }
}
