import AVFoundation
import AppKit
import Speech

/// A saved voice memo on disk, with an optional on-device transcript beside it.
struct VoiceMemo: Identifiable, Equatable {
  let url: URL
  let date: Date
  let duration: TimeInterval
  let transcript: String?
  var id: URL { url }
}

/// Records microphone audio to local M4A files and transcribes them on device.
@MainActor
final class VoiceRecorderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
  static let shared = VoiceRecorderModel()
  @Published private(set) var memos: [VoiceMemo] = []
  @Published private(set) var isRecording = false
  @Published private(set) var recordingStarted: Date?
  @Published private(set) var playing: URL?
  @Published private(set) var transcribing: URL?
  @Published private(set) var message: String?
  /// Set when a refused permission blocks the last action; the view offers the matching Settings pane.
  @Published private(set) var permissionIssue: DictationPermissionIssue?
  /// Live input level 0...1 while recording, for the waveform.
  @Published private(set) var level: Double = 0
  let directory: URL
  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?
  private var meter: Timer?

  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/Recordings", isDirectory: true)
    super.init()
    reload()
  }

  static func fileName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Memo \(formatter.string(from: date)).m4a"
  }

  func reload() {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
    memos = files.filter { $0.pathExtension == "m4a" }.map { url in
      let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
      let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
      let transcript = try? String(
        contentsOf: url.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)
      return VoiceMemo(url: url, date: date, duration: duration, transcript: transcript)
    }
    .sorted { $0.date > $1.date }
  }

  func toggleRecording() async {
    if isRecording { stopRecording() } else { await startRecording() }
  }

  func startRecording(now: Date = .now) async {
    guard !isRecording else { return }
    permissionIssue = nil
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      message = "The microphone is off for Brim. Turn it on, then record again."
      permissionIssue = .microphone
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let url = directory.appendingPathComponent(Self.fileName(for: now))
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true
      guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
      self.recorder = recorder
      isRecording = true
      recordingStarted = now
      message = nil
      meter = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.updateLevel() }
      }
    } catch { message = "Couldn’t start recording. \(error.localizedDescription)" }
  }

  func stopRecording() {
    recorder?.stop()
    recorder = nil
    meter?.invalidate()
    meter = nil
    level = 0
    isRecording = false
    recordingStarted = nil
    reload()
    IslandFlashCenter.shared.show("Memo saved", symbol: "waveform", tint: .red)
  }

  private func updateLevel() {
    guard let recorder else { return }
    recorder.updateMeters()
    let power = recorder.averagePower(forChannel: 0)
    level = Double(max(0, min(1, (power + 50) / 50)))
  }

  func togglePlayback(_ memo: VoiceMemo) {
    if playing == memo.url {
      player?.stop()
      playing = nil
      return
    }
    do {
      let player = try AVAudioPlayer(contentsOf: memo.url)
      player.delegate = self
      player.play()
      self.player = player
      playing = memo.url
    } catch { message = "Couldn’t play this memo." }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.playing = nil }
  }

  func delete(_ memo: VoiceMemo) {
    if playing == memo.url { player?.stop(); playing = nil }
    try? FileManager.default.trashItem(at: memo.url, resultingItemURL: nil)
    try? FileManager.default.removeItem(at: memo.url.deletingPathExtension().appendingPathExtension("txt"))
    reload()
  }

  func reveal(_ memo: VoiceMemo) { NSWorkspace.shared.activateFileViewerSelecting([memo.url]) }

  func copyTranscript(_ memo: VoiceMemo) {
    guard let transcript = memo.transcript else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcript, forType: .string)
    message = "Transcript copied"
  }

  /// Transcribes with Apple's on-device speech engine; audio never leaves the Mac.
  func transcribe(_ memo: VoiceMemo) async {
    guard transcribing == nil else { return }
    permissionIssue = nil
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard status == .authorized else {
      message = "Speech Recognition is off for Brim. Turn it on, then try again."
      permissionIssue = .speechRecognition
      return
    }
    guard let recognizer = OnDeviceSpeech.recognizer(), recognizer.supportsOnDeviceRecognition else {
      message = "On-device speech recognition isn’t available for this language."
      return
    }
    transcribing = memo.url
    defer { transcribing = nil }
    let request = SFSpeechURLRecognitionRequest(url: memo.url)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    do {
      let text: String = try await withCheckedThrowingContinuation { continuation in
        var finished = false
        recognizer.recognitionTask(with: request) { result, error in
          guard !finished else { return }
          if let error {
            finished = true
            continuation.resume(throwing: error)
          } else if let result, result.isFinal {
            finished = true
            continuation.resume(returning: result.bestTranscription.formattedString)
          }
        }
      }
      try text.write(
        to: memo.url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
      reload()
      message = text.isEmpty ? "No speech found" : "Transcribed"
    } catch {
      // 1110 is the speech engine saying it heard nothing, not a failure.
      message = (error as NSError).code == 1110 ? "No speech found" : "Couldn’t transcribe. \(error.localizedDescription)"
    }
  }
}
