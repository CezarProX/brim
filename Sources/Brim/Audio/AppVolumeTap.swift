import AudioToolbox
import CoreAudio
import Foundation

enum AppVolumeTapError: LocalizedError, Equatable {
  case noProcesses, unsupported
  case system(String, Int32)

  /// True when macOS refused because Brim lacks System Audio Recording access.
  var isPermission: Bool {
    if case let .system(_, status) = self {
      return status == kAudioHardwareIllegalOperationError || status == kAudioHardwareNotRunningError
    }
    return false
  }

  var errorDescription: String? {
    switch self {
    case .noProcesses: return "That app is not playing audio right now."
    case .unsupported: return "Per-app volume needs macOS 14.2 or newer."
    case let .system(step, status):
      if status == kAudioHardwareIllegalOperationError || status == kAudioHardwareNotRunningError {
        return "Allow Brim in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only."
      }
      return "Could not \(step) (Core Audio error \(status))."
    }
  }
}

/// Changes one app's volume: taps its audio (silencing the original), then plays the tapped stream
/// through an aggregate device onto `outputUID` with gain applied in the IOProc.
///
/// Realtime rules for the IOProc: no allocation, no locks, no Swift runtime calls that can block. The
/// target gain lives in a raw Float cell that the main thread stores and the audio thread loads.
@available(macOS 14.2, *)
final class AppVolumeTap: @unchecked Sendable {
  private let queue = DispatchQueue(label: "brim.app-volume", qos: .userInteractive)
  private let targetCell = UnsafeMutablePointer<Float>.allocate(capacity: 1)
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private(set) var processes: [UInt32] = []
  private(set) var outputUID: String = ""
  private(set) var isRunning = false

  init() { targetCell.initialize(to: 1) }
  deinit {
    stop()
    targetCell.deallocate()
  }

  /// Target linear gain; the IOProc glides to it, so calling this during a drag is click-free.
  func setGain(_ value: Float) { targetCell.pointee = value.isFinite ? max(0, value) : 1 }

  func start(processes: [UInt32], outputUID: String, gain: Float) throws {
    stop()
    guard !processes.isEmpty else { throw AppVolumeTapError.noProcesses }
    setGain(gain)
    let description = CATapDescription(stereoMixdownOfProcesses: processes.map { AudioObjectID($0) })
    description.uuid = UUID()
    description.muteBehavior = .mutedWhenTapped
    description.isPrivate = true
    var status = AudioHardwareCreateProcessTap(description, &tapID)
    guard status == noErr else { throw cleanup(.system("tap the app", status)) }

    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Brim App Volume",
      kAudioAggregateDeviceUIDKey: "Brim-\(UUID().uuidString)",
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
      ],
    ]
    status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
    guard status == noErr else { throw cleanup(.system("create the audio route", status)) }

    let cell = targetCell
    let tapChannels = Self.tapChannelCount(tapID)
    let state = RenderState(initial: cell.pointee)
    status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, output, _ in
      Self.render(input: input, output: output, tapChannels: tapChannels, state: state, target: cell.pointee)
    }
    guard status == noErr, let procID else { throw cleanup(.system("start the audio route", status)) }
    status = AudioDeviceStart(aggregateID, procID)
    guard status == noErr else { throw cleanup(.system("start the audio route", status)) }
    self.processes = processes
    self.outputUID = outputUID
    isRunning = true
  }

  func stop() {
    if let procID, aggregateID != kAudioObjectUnknown {
      AudioDeviceStop(aggregateID, procID)
      AudioDeviceDestroyIOProcID(aggregateID, procID)
    }
    procID = nil
    if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
    // Destroying the tap restores the app's own output immediately.
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    aggregateID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
    processes = []
    isRunning = false
  }

  private func cleanup(_ error: AppVolumeTapError) -> AppVolumeTapError {
    stop()
    return error
  }

  private static func tapChannelCount(_ tap: AudioObjectID) -> Int {
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var address = CoreAudioProperty.address(kAudioTapPropertyFormat)
    guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr, format.mChannelsPerFrame > 0 else {
      return 2
    }
    return Int(format.mChannelsPerFrame)
  }

  /// Audio thread. Copies the tapped stream to the output buffers, scaled by the gliding gain.
  /// Every output buffer starts from the same smoother state, so channels split across buffers stay in phase.
  fileprivate static func render(
    input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
    tapChannels: Int, state: RenderState, target: Float
  ) {
    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    let outs = UnsafeMutableAudioBufferListPointer(output)
    // The tap is appended after any sub-device input streams, so it is the last buffer.
    guard let tap = ins.last(where: { Int($0.mNumberChannels) == tapChannels }) ?? ins.last,
          let tapData = tap.mData?.assumingMemoryBound(to: Float.self) else {
      for index in 0..<outs.count { if let d = outs[index].mData { memset(d, 0, Int(outs[index].mDataByteSize)) } }
      return
    }
    let inCh = max(1, Int(tap.mNumberChannels))
    let inFrames = Int(tap.mDataByteSize) / (MemoryLayout<Float>.size * inCh)
    let start = state.smoother
    var end = start
    var firstChannel = 0
    for index in 0..<outs.count {
      guard let out = outs[index].mData?.assumingMemoryBound(to: Float.self) else { continue }
      let outCh = max(1, Int(outs[index].mNumberChannels))
      let outFrames = Int(outs[index].mDataByteSize) / (MemoryLayout<Float>.size * outCh)
      var g = start
      for frame in 0..<outFrames {
        let gain = g.next(toward: target)
        for c in 0..<outCh {
          let source = firstChannel + c
          guard frame < inFrames, source < inCh else { out[frame * outCh + c] = 0; continue }
          let sample = tapData[frame * inCh + source] * gain
          out[frame * outCh + c] = gain > 1 ? AudioGainMath.softClip(sample) : sample
        }
      }
      end = g
      firstChannel += outCh
    }
    state.smoother = end
  }
}

/// Mutable IOProc state, owned by the audio thread once the proc is running.
final class RenderState: @unchecked Sendable {
  var smoother: GainSmoother
  init(initial: Float) { smoother = GainSmoother(initial: initial) }
}
