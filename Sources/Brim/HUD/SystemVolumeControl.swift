import AudioToolbox
import CoreAudio
import Foundation

/// Reads and writes the default output device's volume and mute through CoreAudio.
/// Every call returns nil/false when the device has no software volume (HDMI, some DACs), which
/// lets the caller leave the key event alone instead of swallowing a press that does nothing.
enum SystemVolumeControl {
  struct State: Equatable {
    var level: Double
    var muted: Bool
  }

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
  }

  static func defaultOutputDevice() -> AudioDeviceID? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var request = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &request, 0, nil, &size, &device)
    return status == noErr && device != 0 ? device : nil
  }

  static func read() -> State? {
    guard let device = defaultOutputDevice() else { return nil }
    var request = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    var level: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectHasProperty(device, &request),
      AudioObjectGetPropertyData(device, &request, 0, nil, &size, &level) == noErr
    else { return nil }
    return State(level: HUDLevelMath.clamp(Double(level)), muted: readMute(device) ?? false)
  }

  private static func readMute(_ device: AudioDeviceID) -> Bool? {
    var request = address(kAudioDevicePropertyMute)
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectHasProperty(device, &request),
      AudioObjectGetPropertyData(device, &request, 0, nil, &size, &muted) == noErr
    else { return nil }
    return muted != 0
  }

  @discardableResult
  static func setLevel(_ level: Double) -> Bool {
    guard let device = defaultOutputDevice() else { return false }
    var request = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    var settable: DarwinBoolean = false
    guard AudioObjectHasProperty(device, &request),
      AudioObjectIsPropertySettable(device, &request, &settable) == noErr, settable.boolValue
    else { return false }
    var value = Float32(HUDLevelMath.clamp(level))
    return AudioObjectSetPropertyData(device, &request, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
  }

  @discardableResult
  static func setMuted(_ muted: Bool) -> Bool {
    guard let device = defaultOutputDevice() else { return false }
    var request = address(kAudioDevicePropertyMute)
    var settable: DarwinBoolean = false
    guard AudioObjectHasProperty(device, &request),
      AudioObjectIsPropertySettable(device, &request, &settable) == noErr, settable.boolValue
    else { return false }
    var value: UInt32 = muted ? 1 : 0
    return AudioObjectSetPropertyData(device, &request, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
  }

  /// The state after a key press, as pure data: stepping up unmutes; stepping down to zero shows muted.
  static func applying(_ key: MediaKey, fine: Bool, to state: State) -> State {
    switch key {
    case .mute:
      return State(level: state.level, muted: !state.muted)
    case .soundUp, .soundDown:
      let level = HUDLevelMath.next(from: state.level, direction: key.direction, fine: fine)
      return State(level: level, muted: key == .soundUp ? false : state.muted && level > 0)
    default:
      return state
    }
  }

  /// Applies a key press to the hardware and returns the resulting state, or nil if the device
  /// cannot be controlled (the caller should then pass the event through).
  static func handle(_ key: MediaKey, fine: Bool) -> State? {
    guard let before = read() else { return nil }
    let after = applying(key, fine: fine, to: before)
    if after.level != before.level, !setLevel(after.level) { return nil }
    if after.muted != before.muted, !setMuted(after.muted) { return nil }
    return after
  }
}
