import AVFoundation
import AppKit
import ApplicationServices
import Combine
import Foundation
import Speech

@MainActor
protocol DictationSpeechProviding: AnyObject {
  var supportsOnDeviceRecognition: Bool { get }
  func requestAuthorization() async throws
  func begin(
    update: @escaping (String, Bool) -> Void,
    failure: @escaping (Error) -> Void
  ) throws
  func stop()
}

@MainActor
protocol DictationInsertionProviding: AnyObject {
  func captureFocusedTarget() -> Bool
  func insert(_ text: String) throws
  func discardTarget()
}

@MainActor
protocol DictationClipboardWriting: AnyObject {
  func copy(_ text: String)
}

/// A privacy switch the user has to turn on before dictation can listen.
enum DictationPermissionIssue: Equatable {
  case microphone, speechRecognition

  var settingsURL: URL {
    let pane = self == .microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
    return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
  }
}

@MainActor
final class DictationModel: ObservableObject {
  static let shared = DictationModel()

  @Published private(set) var isRecording = false
  @Published private(set) var isStarting = false
  @Published private(set) var transcript = ""
  @Published private(set) var errorMessage: String?
  @Published private(set) var hasInsertionTarget = false
  @Published private(set) var lastActionMessage: String?
  /// Which privacy switch to point the user at when a permission was refused.
  @Published var permissionIssue: DictationPermissionIssue?

  var canCopy: Bool { !transcript.isEmpty }
  var canInsert: Bool { !isRecording && hasInsertionTarget && !transcript.isEmpty }

  private let speech: any DictationSpeechProviding
  private let insertion: any DictationInsertionProviding
  private let clipboard: any DictationClipboardWriting
  private let maximumDuration: Duration
  private let targetRetentionDuration: Duration
  private var sessionGeneration = 0
  private var targetGeneration = 0
  private var deadlineTask: Task<Void, Never>?
  private var targetExpiryTask: Task<Void, Never>?

  init(
    speech: (any DictationSpeechProviding)? = nil,
    insertion: (any DictationInsertionProviding)? = nil,
    clipboard: (any DictationClipboardWriting)? = nil,
    maximumDuration: Duration = .seconds(300),
    targetRetentionDuration: Duration = .seconds(600)
  ) {
    self.speech = speech ?? OnDeviceDictationSpeechProvider()
    self.insertion = insertion ?? AccessibilityDictationInsertionProvider()
    self.clipboard = clipboard ?? SystemDictationClipboard()
    self.maximumDuration = max(maximumDuration, .milliseconds(10))
    self.targetRetentionDuration = max(targetRetentionDuration, .milliseconds(10))
  }

  /// Captures the currently focused text element before permission sheets can move focus.
  /// This method is the only path that requests microphone and Speech consent.
  func start() async {
    guard !isRecording, !isStarting else { return }
    sessionGeneration &+= 1
    let generation = sessionGeneration
    deadlineTask?.cancel()
    targetExpiryTask?.cancel()
    speech.stop()
    targetGeneration &+= 1
    let targetGeneration = targetGeneration
    insertion.discardTarget()
    hasInsertionTarget = insertion.captureFocusedTarget()
    if hasInsertionTarget { scheduleTargetExpiry(for: targetGeneration) }
    transcript = ""
    errorMessage = nil
    permissionIssue = nil
    lastActionMessage = nil
    isStarting = true

    do {
      try await speech.requestAuthorization()
      guard generation == sessionGeneration, isStarting else { return }
      guard speech.supportsOnDeviceRecognition else {
        throw DictationError.onDeviceRecognitionUnavailable
      }
      isRecording = true
      try speech.begin(
        update: { [weak self] text, isFinal in
          Task { @MainActor in self?.receive(text, isFinal: isFinal, generation: generation) }
        },
        failure: { [weak self] error in
          Task { @MainActor in self?.fail(error, generation: generation) }
        }
      )
      guard generation == sessionGeneration else {
        speech.stop()
        isRecording = false
        return
      }
      isStarting = false
      scheduleDeadline(for: generation)
    } catch {
      guard generation == sessionGeneration else { return }
      speech.stop()
      isRecording = false
      isStarting = false
      errorMessage = error.localizedDescription
      permissionIssue = (error as? DictationError)?.permissionIssue
    }
  }

  func stop() {
    sessionGeneration &+= 1
    stopSpeechResources()
  }

  func copy() {
    guard !transcript.isEmpty else { return }
    if isRecording || isStarting { stop() }
    clipboard.copy(transcript)
    lastActionMessage = "Copied"
    errorMessage = nil
  }

  func insert() throws {
    guard canInsert else {
      let error = DictationError.insertionTargetUnavailable
      errorMessage = error.localizedDescription
      throw error
    }
    do {
      try insertion.insert(transcript)
      targetGeneration &+= 1
      targetExpiryTask?.cancel()
      targetExpiryTask = nil
      insertion.discardTarget()
      hasInsertionTarget = false
      lastActionMessage = "Inserted"
      errorMessage = nil
    } catch {
      targetGeneration &+= 1
      targetExpiryTask?.cancel()
      targetExpiryTask = nil
      insertion.discardTarget()
      hasInsertionTarget = false
      errorMessage = error.localizedDescription
      throw error
    }
  }

  private func receive(_ text: String, isFinal: Bool, generation: Int) {
    guard generation == sessionGeneration, isRecording else { return }
    transcript = String(text.prefix(50_000))
    if isFinal {
      sessionGeneration &+= 1
      stopSpeechResources()
    }
  }

  private func fail(_ error: Error, generation: Int) {
    guard generation == sessionGeneration, isRecording || isStarting else { return }
    sessionGeneration &+= 1
    stopSpeechResources()
    errorMessage = error.localizedDescription
  }

  private func scheduleDeadline(for generation: Int) {
    let duration = maximumDuration
    deadlineTask = Task { [weak self] in
      do { try await Task.sleep(for: duration) } catch { return }
      guard let self, generation == self.sessionGeneration, self.isRecording else { return }
      self.sessionGeneration &+= 1
      self.stopSpeechResources()
      self.errorMessage = DictationError.sessionExpired.localizedDescription
    }
  }

  private func scheduleTargetExpiry(for generation: Int) {
    let duration = targetRetentionDuration
    targetExpiryTask = Task { [weak self] in
      do { try await Task.sleep(for: duration) } catch { return }
      guard let self, generation == self.targetGeneration else { return }
      self.insertion.discardTarget()
      self.hasInsertionTarget = false
      self.targetExpiryTask = nil
    }
  }

  private func stopSpeechResources() {
    deadlineTask?.cancel()
    deadlineTask = nil
    speech.stop()
    isRecording = false
    isStarting = false
  }
}

/// Picks the speech recognizer for this Mac.
enum OnDeviceSpeech {
  /// The first recognizer that can run on this Mac, trying the system region, then each preferred
  /// language, then US English, so a Romanian or other UI language still finds a working engine.
  static func recognizer() -> SFSpeechRecognizer? {
    let candidates = [Locale.current] + Locale.preferredLanguages.map { Locale(identifier: $0) } + [Locale(identifier: "en-US")]
    for locale in candidates {
      if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition { return recognizer }
    }
    return SFSpeechRecognizer()
  }
}

@MainActor
private final class OnDeviceDictationSpeechProvider: DictationSpeechProviding {
  private let recognizer: SFSpeechRecognizer?
  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var hasInputTap = false

  init(locale: Locale? = nil) {
    recognizer = locale.flatMap { SFSpeechRecognizer(locale: $0) } ?? OnDeviceSpeech.recognizer()
  }

  var supportsOnDeviceRecognition: Bool {
    recognizer?.supportsOnDeviceRecognition == true
  }

  func requestAuthorization() async throws {
    let speechStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speechStatus == .authorized else { throw DictationError.speechPermissionDenied }
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw DictationError.microphonePermissionDenied
    }
  }

  func begin(
    update: @escaping (String, Bool) -> Void,
    failure: @escaping (Error) -> Void
  ) throws {
    stop()
    guard let recognizer, recognizer.supportsOnDeviceRecognition else {
      throw DictationError.onDeviceRecognitionUnavailable
    }
    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw DictationError.microphoneUnavailable
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    self.request = request
    input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
      request.append(buffer)
    }
    hasInputTap = true
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stop()
      throw DictationError.couldNotStartMicrophone
    }
    recognitionTask = recognizer.recognitionTask(with: request) { result, error in
      if let result {
        update(result.bestTranscription.formattedString, result.isFinal)
      }
      if let error { failure(error) }
    }
  }

  func stop() {
    if audioEngine.isRunning { audioEngine.stop() }
    if hasInputTap {
      audioEngine.inputNode.removeTap(onBus: 0)
      hasInputTap = false
    }
    request?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    request = nil
  }
}

@MainActor
private final class SystemDictationClipboard: DictationClipboardWriting {
  func copy(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}

@MainActor
private final class AccessibilityDictationInsertionProvider: DictationInsertionProviding {
  private struct Target {
    let element: AXUIElement
    let pid: pid_t
    let bundleIdentifier: String
    let role: String
    let subrole: String?
  }

  private var target: Target?

  func captureFocusedTarget() -> Bool {
    target = nil
    guard AXIsProcessTrusted(), let element = Self.focusedElement(AXUIElementCreateSystemWide())
    else { return false }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid != getpid(),
      let app = NSRunningApplication(processIdentifier: pid),
      let bundleIdentifier = app.bundleIdentifier,
      let role = Self.stringAttribute(element, kAXRoleAttribute),
      Self.acceptedRoles.contains(role), !Self.isSecure(element),
      Self.supportsInsertion(element)
    else { return false }
    target = Target(
      element: element,
      pid: pid,
      bundleIdentifier: bundleIdentifier,
      role: role,
      subrole: Self.stringAttribute(element, kAXSubroleAttribute)
    )
    return true
  }

  func insert(_ text: String) throws {
    guard text.utf16.count <= 50_000, let target else {
      throw DictationError.insertionTargetUnavailable
    }
    guard AXIsProcessTrusted(),
      let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
      app.bundleIdentifier == target.bundleIdentifier
    else { throw DictationError.insertionTargetChanged }
    let application = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(application, 0.25)
    guard let focused = Self.focusedElement(application), CFEqual(focused, target.element),
      Self.matches(target, element: focused), !Self.isSecure(focused)
    else {
      throw DictationError.insertionTargetChanged
    }
    guard Self.write(text, to: focused) else { throw DictationError.insertionFailed }
  }

  func discardTarget() { target = nil }

  private static let acceptedRoles: Set<String> = [
    kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
  ]

  private static func matches(_ target: Target, element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success
      && pid == target.pid
      && stringAttribute(element, kAXRoleAttribute) == target.role
      && stringAttribute(element, kAXSubroleAttribute) == target.subrole
      && supportsInsertion(element)
  }

  private static func isSecure(_ element: AXUIElement) -> Bool {
    var current: AXUIElement? = element
    for _ in 0..<8 {
      guard let node = current else { return false }
      if stringAttribute(node, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
        || (attribute(node, NSAccessibility.Attribute.containsProtectedContent.rawValue)
          as? NSNumber)?.boolValue == true
      {
        return true
      }
      current = elementAttribute(node, kAXParentAttribute)
    }
    // An unexpectedly deep protected hierarchy is not safe to write into.
    return current != nil
  }

  private static func supportsInsertion(_ element: AXUIElement) -> Bool {
    isSettable(element, kAXSelectedTextAttribute)
  }

  private static func write(_ text: String, to element: AXUIElement) -> Bool {
    guard isSettable(element, kAXSelectedTextAttribute) else { return false }
    return AXUIElementSetAttributeValue(
      element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
  }

  private static func focusedElement(_ root: AXUIElement) -> AXUIElement? {
    guard let value = attribute(root, kAXFocusedUIElementAttribute),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
      && settable.boolValue
  }

  private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
  }

  private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }
}

private enum DictationError: LocalizedError {
  case speechPermissionDenied
  case microphonePermissionDenied
  case onDeviceRecognitionUnavailable
  case microphoneUnavailable
  case couldNotStartMicrophone
  case sessionExpired
  case insertionTargetUnavailable
  case insertionTargetChanged
  case insertionFailed

  var permissionIssue: DictationPermissionIssue? {
    switch self {
    case .speechPermissionDenied: .speechRecognition
    case .microphonePermissionDenied: .microphone
    default: nil
    }
  }

  var errorDescription: String? {
    switch self {
    case .speechPermissionDenied:
      "Speech Recognition is off for Brim. Turn it on, then try again."
    case .microphonePermissionDenied:
      "The microphone is off for Brim. Turn it on, then try again."
    case .onDeviceRecognitionUnavailable:
      "On-device speech recognition is unavailable for the current language. No audio was sent to a server."
    case .microphoneUnavailable:
      "No usable microphone input is available."
    case .couldNotStartMicrophone:
      "Brim could not start the microphone."
    case .sessionExpired:
      "Dictation stopped at the five-minute time limit."
    case .insertionTargetUnavailable:
      "No original editable text field is available. Copy the text instead."
    case .insertionTargetChanged:
      "The original text field changed or is no longer focused. Copy the text instead."
    case .insertionFailed:
      "The original text field refused the insertion. Copy the text instead."
    }
  }
}
