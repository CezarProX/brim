import CoreAudio
import Foundation
import SwiftUI

/// What the mute logic needs from the audio system. `CoreAudioInputs` is the real one; tests use a fake.
protocol AudioInputControlling {
  func inputDevices() -> [UInt32]
  /// nil when the device has no mute control.
  func isMuted(_ device: UInt32) -> Bool?
  @discardableResult func setMuted(_ device: UInt32, _ muted: Bool) -> Bool
}

enum MicrophoneMuteLogic {
  /// Muting wins when any microphone is live; otherwise the toggle unmutes everything.
  static func target(states: [Bool?]) -> Bool {
    let known = states.compactMap { $0 }
    return known.isEmpty ? true : known.contains(false)
  }

  static func isMuted(states: [Bool?]) -> Bool {
    let known = states.compactMap { $0 }
    return !known.isEmpty && !known.contains(false)
  }
}

/// System-wide microphone mute: every input device that supports it, so a call app can't keep listening on another.
@MainActor
final class MicrophoneMuteController: ObservableObject {
  static let shared = MicrophoneMuteController()
  @Published private(set) var isMuted = false
  private let inputs: AudioInputControlling

  init(inputs: AudioInputControlling = CoreAudioInputs()) {
    self.inputs = inputs
    refresh()
  }

  func refresh() {
    let next = MicrophoneMuteLogic.isMuted(states: inputs.inputDevices().map(inputs.isMuted))
    if next != isMuted { isMuted = next }
  }

  /// Toggles every microphone and returns the new muted state, or nil if no device supports muting.
  @discardableResult
  func toggle(announce: Bool = true) -> Bool? {
    let devices = inputs.inputDevices()
    let target = MicrophoneMuteLogic.target(states: devices.map(inputs.isMuted))
    var changed = false
    for device in devices where inputs.isMuted(device) != nil {
      changed = inputs.setMuted(device, target) || changed
    }
    refresh()
    guard changed else {
      if announce {
        IslandFlashCenter.shared.show("Mic can't be muted", symbol: "mic.slash", tint: .orange)
      }
      return nil
    }
    if announce {
      IslandFlashCenter.shared.show(
        isMuted ? "Microphones muted" : "Microphones on", symbol: isMuted ? "mic.slash.fill" : "mic.fill",
        tint: isMuted ? .red : .green, duration: 1.6)
    }
    return isMuted
  }
}

/// CoreAudio: the mute switch on each input device, falling back to the input volume when a device has none.
final class CoreAudioInputs: AudioInputControlling {
  private var savedVolume: [UInt32: Float32] = [:]

  func inputDevices() -> [UInt32] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
      return []
    }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids.filter(hasInput)
  }

  private func hasInput(_ device: AudioObjectID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return false }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
  }

  private func address(_ selector: AudioObjectPropertySelector, element: UInt32 = kAudioObjectPropertyElementMain)
    -> AudioObjectPropertyAddress
  {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
  }

  func isMuted(_ device: UInt32) -> Bool? {
    var muteAddress = address(kAudioDevicePropertyMute)
    if AudioObjectHasProperty(device, &muteAddress) {
      var value: UInt32 = 0
      var size = UInt32(MemoryLayout<UInt32>.size)
      if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr { return value != 0 }
    }
    var volumeAddress = address(kAudioDevicePropertyVolumeScalar)
    if AudioObjectHasProperty(device, &volumeAddress) {
      var value: Float32 = 0
      var size = UInt32(MemoryLayout<Float32>.size)
      if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr { return value <= 0.001 }
    }
    return nil
  }

  func setMuted(_ device: UInt32, _ muted: Bool) -> Bool {
    var muteAddress = address(kAudioDevicePropertyMute)
    if AudioObjectHasProperty(device, &muteAddress) {
      var value: UInt32 = muted ? 1 : 0
      if AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
        return true
      }
    }
    var volumeAddress = address(kAudioDevicePropertyVolumeScalar)
    guard AudioObjectHasProperty(device, &volumeAddress) else { return false }
    var current: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    _ = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &current)
    if muted, current > 0.001 { savedVolume[device] = current }
    var value: Float32 = muted ? 0 : (savedVolume[device] ?? 0.75)
    return AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
  }
}
