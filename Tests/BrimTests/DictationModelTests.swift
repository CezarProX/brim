import Foundation
import Testing

@testable import Brim

@MainActor
private final class StubDictationSpeechProvider: DictationSpeechProviding {
  var supportsOnDeviceRecognition = true
  private(set) var authorizationRequests = 0
  private(set) var starts = 0
  private(set) var stops = 0
  var authorizationError: Error?
  private var update: ((String, Bool) -> Void)?
  private var failure: ((Error) -> Void)?

  func requestAuthorization() async throws {
    authorizationRequests += 1
    if let authorizationError { throw authorizationError }
  }

  func begin(
    update: @escaping (String, Bool) -> Void,
    failure: @escaping (Error) -> Void
  ) throws {
    starts += 1
    self.update = update
    self.failure = failure
  }

  func stop() { stops += 1 }
  func emit(_ text: String, final: Bool = false) { update?(text, final) }
  func fail(_ error: Error) { failure?(error) }
}

@MainActor
private final class StubDictationInsertionProvider: DictationInsertionProviding {
  var capturesTarget = true
  private(set) var captures = 0
  private(set) var inserted: [String] = []
  private(set) var discards = 0

  func captureFocusedTarget() -> Bool {
    captures += 1
    return capturesTarget
  }

  func insert(_ text: String) throws { inserted.append(text) }
  func discardTarget() { discards += 1 }
}

@MainActor
private final class StubDictationClipboard: DictationClipboardWriting {
  private(set) var values: [String] = []
  func copy(_ text: String) { values.append(text) }
}

@MainActor
struct DictationModelTests {
  @Test func initializationDoesNotRequestConsentOrInspectFocus() {
    let speech = StubDictationSpeechProvider()
    let insertion = StubDictationInsertionProvider()
    _ = DictationModel(speech: speech, insertion: insertion, clipboard: StubDictationClipboard())

    #expect(speech.authorizationRequests == 0)
    #expect(speech.starts == 0)
    #expect(insertion.captures == 0)
  }

  @Test func explicitStartCapturesTargetAndUsesOnlyOnDeviceRecognition() async {
    let speech = StubDictationSpeechProvider()
    let insertion = StubDictationInsertionProvider()
    let model = DictationModel(
      speech: speech, insertion: insertion, clipboard: StubDictationClipboard())

    await model.start()
    #expect(insertion.captures == 1)
    #expect(speech.authorizationRequests == 1)
    #expect(speech.starts == 1)
    #expect(model.isRecording)

    speech.emit("hello from the Mac")
    await Task.yield()
    #expect(model.transcript == "hello from the Mac")
  }

  @Test func unavailableOnDeviceRecognizerNeverStartsOrFallsBack() async {
    let speech = StubDictationSpeechProvider()
    speech.supportsOnDeviceRecognition = false
    let model = DictationModel(
      speech: speech,
      insertion: StubDictationInsertionProvider(),
      clipboard: StubDictationClipboard()
    )

    await model.start()
    #expect(!model.isRecording)
    #expect(speech.starts == 0)
    #expect(model.errorMessage?.lowercased().contains("on-device") == true)
  }

  @Test func copyAndInsertRequireExplicitMethodsAndStopRecording() async {
    let speech = StubDictationSpeechProvider()
    let insertion = StubDictationInsertionProvider()
    let clipboard = StubDictationClipboard()
    let model = DictationModel(speech: speech, insertion: insertion, clipboard: clipboard)

    await model.start()
    speech.emit("Private local text")
    await Task.yield()
    #expect(clipboard.values.isEmpty)
    #expect(insertion.inserted.isEmpty)

    model.copy()
    #expect(clipboard.values == ["Private local text"])
    #expect(!model.isRecording)

    try? model.insert()
    #expect(insertion.inserted == ["Private local text"])
    #expect(!model.canInsert)
  }

  @Test func stoppingDuringAuthorizationPreventsLateRecognitionStart() async {
    let speech = SuspendedDictationSpeechProvider()
    let model = DictationModel(
      speech: speech,
      insertion: StubDictationInsertionProvider(),
      clipboard: StubDictationClipboard()
    )

    let start = Task { await model.start() }
    await Task.yield()
    model.stop()
    speech.finishAuthorization()
    await start.value

    #expect(!model.isRecording)
    #expect(speech.starts == 0)
  }

  @Test func sessionDeadlineStopsAudioResources() async throws {
    let speech = StubDictationSpeechProvider()
    let model = DictationModel(
      speech: speech,
      insertion: StubDictationInsertionProvider(),
      clipboard: StubDictationClipboard(),
      maximumDuration: .milliseconds(10)
    )

    await model.start()
    let timeout = ContinuousClock.now.advanced(by: .seconds(3))
    while model.isRecording && ContinuousClock.now < timeout {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!model.isRecording)
    #expect(speech.stops >= 1)
    #expect(model.errorMessage?.contains("time limit") == true)
  }

  @Test func capturedAccessibilityTargetExpires() async throws {
    let insertion = StubDictationInsertionProvider()
    let model = DictationModel(
      speech: StubDictationSpeechProvider(),
      insertion: insertion,
      clipboard: StubDictationClipboard(),
      targetRetentionDuration: .milliseconds(10)
    )

    await model.start()
    #expect(model.hasInsertionTarget)
    let timeout = ContinuousClock.now.advanced(by: .seconds(3))
    while model.hasInsertionTarget && ContinuousClock.now < timeout {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!model.hasInsertionTarget)
    #expect(insertion.discards >= 2)
  }
}

@MainActor
private final class SuspendedDictationSpeechProvider: DictationSpeechProviding {
  var supportsOnDeviceRecognition = true
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var starts = 0

  func requestAuthorization() async throws {
    await withCheckedContinuation { continuation = $0 }
  }

  func begin(update: @escaping (String, Bool) -> Void, failure: @escaping (Error) -> Void) throws {
    starts += 1
  }

  func stop() {}
  func finishAuthorization() {
    continuation?.resume()
    continuation = nil
  }
}
