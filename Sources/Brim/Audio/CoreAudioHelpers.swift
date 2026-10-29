import CoreAudio
import Foundation

/// Small typed readers over `AudioObjectGetPropertyData`. All return nil on failure.
enum CoreAudioProperty {
  static let system = AudioObjectID(kAudioObjectSystemObject)

  static func address(
    _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var addr = address(selector, scope: scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
  }

  static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
    var addr = address(selector, scope: scope)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
  }

  static func float32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Float32? {
    var addr = address(selector, scope: scope)
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
  }

  @discardableResult
  static func setFloat32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
    var addr = address(selector, scope: scope)
    var settable: DarwinBoolean = false
    guard AudioObjectIsPropertySettable(object, &addr, &settable) == noErr, settable.boolValue else { return false }
    var v = value
    return AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
  }

  /// A property that is an array of object ids (device list, process list, ...), bounded.
  static func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var addr = address(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0, size <= 65_536 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
    var capacity = UInt32(ids.count * MemoryLayout<AudioObjectID>.stride)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &capacity, &ids) == noErr else { return [] }
    return Array(ids.prefix(Int(capacity) / MemoryLayout<AudioObjectID>.stride))
  }
}

/// Reads the live process list. Read-only: safe to call at any time.
struct CoreAudioProcessLister: AudioProcessListing {
  func processes() -> [AudioProcessInfo] {
    CoreAudioProperty.objectIDs(CoreAudioProperty.system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
      guard let bundle = CoreAudioProperty.string(id, kAudioProcessPropertyBundleID), !bundle.isEmpty,
            let pid = CoreAudioProperty.uint32(id, kAudioProcessPropertyPID) else { return nil }
      return AudioProcessInfo(
        objectID: id, pid: Int32(truncatingIfNeeded: pid), bundleID: bundle,
        isRunningOutput: (CoreAudioProperty.uint32(id, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
        isRunningInput: (CoreAudioProperty.uint32(id, kAudioProcessPropertyIsRunningInput) ?? 0) != 0)
    }
  }
}
