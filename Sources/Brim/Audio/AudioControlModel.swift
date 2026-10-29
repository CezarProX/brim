import AppKit
import Combine
import CoreAudio
import Foundation

struct AudioAppRow: Identifiable, Equatable {
  let entry: AudioAppEntry
  var slider: Double
  var muted: Bool
  var outputUID: String?
  var error: String?
  /// The error is macOS refusing System Audio Recording access (fixable in System Settings).
  var needsPermission = false
  var id: String { entry.id }
  var isNeutral: Bool { AudioGainMath.isNeutral(slider: slider, muted: muted) && outputUID == nil }
}

/// Drives the Audio Control droplet: which apps make sound, their volumes, and the taps that apply them.
@MainActor
final class AudioControlModel: ObservableObject {
  static let shared = AudioControlModel()

  @Published private(set) var rows: [AudioAppRow] = []
  @Published private(set) var outputs: [AudioDeviceRef] = []
  @Published private(set) var defaultOutputUID: String?
  @Published private(set) var globalError: String?

  /// Some row could not be routed because System Audio Recording is not allowed yet.
  var needsPermission: Bool { rows.contains { $0.needsPermission } }
  /// No app carries a volume change yet: the first-run hint is worth showing.
  var isUntouched: Bool { rows.allSatisfy(\.isNeutral) }

  var isSupported: Bool { if #available(macOS 14.2, *) { return true } else { return false } }
  var maxSlider: Double { settings.audioAllowBoost ? AudioGainMath.maxSlider : 1 }
  var curve: VolumeCurve { settings.audioVolumeCurve }

  private let lister: AudioProcessListing
  private let directory: AudioDeviceListing
  private let engine: AppVolumeApplying
  private let settings: AppSettings
  private let appName: (String) -> String
  private var adjustments: [String: SavedAppAudio] = [:]
  private var timer: Timer?
  private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var isActive = false
  private let ownBundleID = Bundle.main.bundleIdentifier

  init(
    lister: AudioProcessListing = CoreAudioProcessLister(),
    directory: AudioDeviceListing = CoreAudioDeviceDirectory(),
    engine: AppVolumeApplying? = nil,
    settings: AppSettings = .shared,
    appName: @escaping (String) -> String = AudioControlModel.resolveAppName
  ) {
    self.lister = lister
    self.directory = directory
    self.engine = engine ?? AppVolumeEngine(directory: directory)
    self.settings = settings
    self.appName = appName
    if settings.audioRememberVolumes { adjustments = settings.audioSavedAppSettings }
  }

  // MARK: Lifecycle

  /// Call when the panel opens (fast polling) and again with false when it closes. Taps stay up either way.
  func setActive(_ active: Bool) {
    isActive = active
    active ? startWatching() : stopWatchingIfIdle()
    if active { refresh() }
  }

  /// Re-applies remembered volumes at launch so a saved setting works before the panel is ever opened.
  func start() {
    guard isSupported else { return }
    if settings.audioRememberVolumes, adjustments.values.contains(where: { !AudioGainMath.isNeutral(slider: $0.slider, muted: $0.muted) || $0.outputUID != nil }) {
      startWatching()
      refresh()
    }
  }

  func stop() {
    stopWatching()
    engine.releaseAll()
  }

  func refresh() {
    outputs = directory.devices().filter { $0.isOutput && !$0.isAggregate }
    defaultOutputUID = directory.defaultDevice(input: false)?.uid
    let processes = lister.processes()
    let pinned = Set(adjustments.filter { !$0.value.isNeutral }.keys).union(engine.activeAppIDs)
    let entries = AudioProcessGrouping.entries(
      from: processes, showPaused: settings.audioShowPausedApps,
      includeSystemSounds: settings.audioIncludeSystemSounds,
      excluding: ownBundleID.map { [$0] } ?? [], alwaysInclude: pinned, name: appName)
    let previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    rows = entries.map { entry in
      let saved = adjustments[entry.id]
      return AudioAppRow(
        entry: entry, slider: min(saved?.slider ?? 1, maxSlider), muted: saved?.muted ?? false,
        outputUID: saved?.outputUID, error: previous[entry.id]?.error,
        needsPermission: previous[entry.id]?.needsPermission ?? false)
    }
    for index in rows.indices {
      // A route that just failed is not retried every poll; it retries when the app's processes change.
      if let old = previous[rows[index].id], old.error != nil,
         old.entry.processObjectIDs == rows[index].entry.processObjectIDs { continue }
      applyToEngine(index)
    }
    // Apps that left the list lose their tap: nothing to adjust, nothing to keep alive.
    let present = Set(rows.map(\.id))
    for id in engine.activeAppIDs where !present.contains(id) { engine.release(appID: id) }
    if engine.activeAppIDs.isEmpty && !isActive { stopWatching() }
  }

  // MARK: Intents

  func setSlider(_ id: String, _ value: Double) {
    mutate(id) { $0.slider = min(AudioGainMath.clampSlider(value), maxSlider); if $0.slider > 0 { $0.muted = false } }
  }

  func toggleMute(_ id: String) { mutate(id) { $0.muted.toggle() } }

  func setOutput(_ id: String, uid: String?) { mutate(id) { $0.outputUID = uid } }

  func reset(_ id: String) { mutate(id) { $0.slider = 1; $0.muted = false; $0.outputUID = nil } }

  /// Called when the Natural/Linear curve changes.
  func curveChanged() { for index in rows.indices { applyToEngine(index) } }

  func clearRemembered() {
    adjustments = [:]
    settings.audioSavedAppSettings = [:]
  }

  // MARK: Internals

  private func mutate(_ id: String, _ change: (inout AudioAppRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    var row = rows[index]
    change(&row)
    row.error = nil
    row.needsPermission = false
    rows[index] = row
    adjustments[id] = SavedAppAudio(slider: row.slider, muted: row.muted, outputUID: row.outputUID)
    if settings.audioRememberVolumes { settings.audioSavedAppSettings = adjustments.filter { !$0.value.isNeutral } }
    applyToEngine(index)
    startWatching()
  }

  private func applyToEngine(_ index: Int) {
    let row = rows[index]
    guard isSupported else { return }
    if row.isNeutral { engine.release(appID: row.id); return }
    let gain = AudioGainMath.gain(slider: row.slider, curve: curve, muted: row.muted)
    do {
      try engine.apply(appID: row.id, processes: row.entry.processObjectIDs, gain: gain, outputUID: row.outputUID)
    } catch {
      rows[index].error = error.localizedDescription
      rows[index].needsPermission = (error as? AppVolumeTapError)?.isPermission == true
      globalError = error.localizedDescription
    }
  }

  nonisolated static func resolveAppName(_ bundleID: String) -> String {
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
       let name = running.localizedName { return name }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
  }

  // MARK: Watching

  private func startWatching() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    guard listeners.isEmpty else { return }
    for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
      var address = CoreAudioProperty.address(selector)
      let isDefault = selector == kAudioHardwarePropertyDefaultOutputDevice
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
          if isDefault { self?.engine.defaultOutputChanged() }
          self?.refresh()
        }
      }
      AudioObjectAddPropertyListenerBlock(CoreAudioProperty.system, &address, .main, block)
      listeners.append((address, block))
    }
  }

  private func stopWatchingIfIdle() {
    if engine.activeAppIDs.isEmpty { stopWatching() }
  }

  private func stopWatching() {
    timer?.invalidate()
    timer = nil
    for (address, block) in listeners {
      var address = address
      AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.system, &address, .main, block)
    }
    listeners = []
  }
}

private extension SavedAppAudio {
  var isNeutral: Bool { AudioGainMath.isNeutral(slider: slider, muted: muted) && outputUID == nil }
}
