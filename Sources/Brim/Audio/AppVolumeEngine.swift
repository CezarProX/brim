import Foundation

/// What the model needs from the audio layer; tests use a fake.
@MainActor
protocol AppVolumeApplying: AnyObject {
  /// Set the app to `gain` on `outputUID` (nil = system default). Throws a user-facing error.
  func apply(appID: String, processes: [UInt32], gain: Float, outputUID: String?) throws
  func release(appID: String)
  func releaseAll()
  /// The system default output changed: rebuild routes that follow it.
  func defaultOutputChanged()
  var activeAppIDs: Set<String> { get }
}

/// Owns one `AppVolumeTap` per adjusted app and keeps them valid as processes and devices come and go.
@MainActor
final class AppVolumeEngine: AppVolumeApplying {
  private struct Entry {
    var tap: AnyObject
    var processes: [UInt32]
    var followsDefault: Bool
    var gain: Float
    var requestedUID: String?
  }
  private var taps: [String: Entry] = [:]
  private let directory: AudioDeviceListing

  init(directory: AudioDeviceListing = CoreAudioDeviceDirectory()) { self.directory = directory }

  var activeAppIDs: Set<String> { Set(taps.keys) }

  func apply(appID: String, processes: [UInt32], gain: Float, outputUID: String?) throws {
    guard #available(macOS 14.2, *) else { throw AppVolumeTapError.unsupported }
    guard !processes.isEmpty else { release(appID: appID); throw AppVolumeTapError.noProcesses }
    let uid = try resolve(outputUID)
    if var entry = taps[appID], let tap = entry.tap as? AppVolumeTap, tap.isRunning,
       tap.processes == processes, tap.outputUID == uid {
      tap.setGain(gain)
      entry.gain = gain
      taps[appID] = entry
      return
    }
    release(appID: appID)
    let tap = AppVolumeTap()
    try tap.start(processes: processes, outputUID: uid, gain: gain)
    taps[appID] = Entry(tap: tap, processes: processes, followsDefault: outputUID == nil, gain: gain, requestedUID: outputUID)
  }

  func release(appID: String) {
    guard let entry = taps.removeValue(forKey: appID) else { return }
    if #available(macOS 14.2, *) { (entry.tap as? AppVolumeTap)?.stop() }
  }

  func releaseAll() { for id in Array(taps.keys) { release(appID: id) } }

  func defaultOutputChanged() {
    guard #available(macOS 14.2, *) else { return }
    for (id, entry) in taps where entry.followsDefault {
      guard let tap = entry.tap as? AppVolumeTap else { continue }
      // Rebuild on the new default; if that fails, drop the tap so the app is audible again.
      do { try tap.start(processes: entry.processes, outputUID: resolve(nil), gain: entry.gain) }
      catch { release(appID: id) }
    }
  }

  private func resolve(_ uid: String?) throws -> String {
    if let uid, directory.devices().contains(where: { $0.uid == uid && $0.isOutput }) { return uid }
    if let current = directory.defaultDevice(input: false)?.uid { return current }
    throw AppVolumeTapError.system("find an output device", -1)
  }
}
