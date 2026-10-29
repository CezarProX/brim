import AudioToolbox
import CoreAudio
import Foundation
import os

/// Reads the playing app's real audio through a Core Audio process tap (macOS 14.2+),
/// mono-mixed, and publishes raw band levels. Nothing is recorded or stored: each
/// callback is reduced to a few numbers and discarded.
@available(macOS 14.2, *)
final class LiveAudioTap: @unchecked Sendable {
  static let barCount = 6
  private let queue = DispatchQueue(label: "brim.audio-tap", qos: .userInteractive)
  private let lock = OSAllocatedUnfairLock<[Float]>(initialState: [Float](repeating: 0, count: barCount))
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private var analyzer: SpectrumAnalyzer?
  private var sampleRate: Float = 48_000
  private var ring = [Float](repeating: 0, count: SpectrumAnalyzer.size)

  /// Latest raw levels (0...1) from the audio thread.
  var levels: [Float] { lock.withLock { $0 } }
  private(set) var isRunning = false

  /// Starts tapping every audio process belonging to `bundleID` (helpers included, which
  /// browsers need). Returns false when the tap cannot be created, e.g. permission denied.
  func start(bundleID: String) -> Bool {
    stop()
    let processes = Self.processObjects(bundlePrefix: bundleID)
    guard !processes.isEmpty, let analyzer = SpectrumAnalyzer() else { return false }
    self.analyzer = analyzer

    let description = CATapDescription(monoMixdownOfProcesses: processes)
    description.uuid = UUID()
    description.muteBehavior = .unmuted
    description.isPrivate = true
    guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return fail() }

    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
      sampleRate = Float(format.mSampleRate)
    }

    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Brim Visualizer",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
      ],
    ]
    guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else { return fail() }
    let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
      self?.process(input)
    }
    guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else { return fail() }
    isRunning = true
    return true
  }

  func stop() {
    if let procID, aggregateID != kAudioObjectUnknown {
      AudioDeviceStop(aggregateID, procID)
      AudioDeviceDestroyIOProcID(aggregateID, procID)
    }
    procID = nil
    if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    aggregateID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
    isRunning = false
    lock.withLock { $0 = [Float](repeating: 0, count: Self.barCount) }
  }

  private func fail() -> Bool {
    stop()
    return false
  }

  /// Audio thread: fold the buffer into the ring, analyze, publish.
  private func process(_ list: UnsafePointer<AudioBufferList>) {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
    guard let first = buffers.first, let data = first.mData, first.mDataByteSize >= 4 else { return }
    let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
    let channels = max(1, Int(first.mNumberChannels))
    let samples = data.assumingMemoryBound(to: Float.self)
    let mono = frames / channels
    let keep = min(mono, ring.count)
    ring.removeFirst(keep)
    for frame in (mono - keep)..<mono {
      var sum: Float = 0
      for channel in 0..<channels { sum += samples[frame * channels + channel] }
      ring.append(sum / Float(channels))
    }
    guard let analyzer else { return }
    let result = ring.withUnsafeBufferPointer {
      analyzer.levels(samples: $0, sampleRate: sampleRate, bars: Self.barCount)
    }
    lock.withLock { $0 = result }
  }

  // MARK: - Process lookup

  private static func processObjects(bundlePrefix: String) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
      size > 0
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids.filter { id in
      guard let bundle = bundleID(of: id) else { return false }
      return bundle == bundlePrefix || bundle.hasPrefix(bundlePrefix + ".")
    }
  }

  private static func bundleID(of object: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
  }
}
