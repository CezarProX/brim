// WebReplySender.swift
// Brim
//
// One reply through a web messenger, as a short sequence of page scripts driven from Swift so
// every step has its own bounded wait: page ready -> chat open -> text typed -> Send pressed ->
// message confirmed -> chat closed. Each script call also has a hard timeout.

import Foundation

struct ReplyPacing: Sendable {
  /// Polls while the page is still loading (a cold WhatsApp Web start takes several seconds).
  var readyAttempts = 40
  /// Polls for the conversation header after clicking its row or searching.
  var chatAttempts = 12
  /// Polls for the composer to clear and the outgoing bubble to appear.
  var confirmAttempts = 16
  var interval: Duration = .milliseconds(500)
  /// Upper bound for any single script call.
  var scriptTimeout: Duration = .seconds(8)

  static let standard = ReplyPacing()
}

@MainActor
struct WebReplySender {
  let driver: WebPageDriving
  let profile: WebMessengerProfile
  var pacing: ReplyPacing = .standard

  func send(text: String, names: [String]) async throws {
    try await waitUntilReady()
    try await openChat(names: names)
    try await compose(text)
    let before = try await pressSend()
    try await confirm(text: text, before: before)
    _ = try? await run(profile.closeChat)
  }

  // MARK: Steps

  /// Throws `.notConnected` when the page shows the login screen.
  func waitUntilReady() async throws {
    for attempt in 0..<pacing.readyAttempts {
      switch WebPageStatus(rawValue: try await run(profile.status).string) {
      case .connected: return
      case .login, .unsupported: throw ReplyError.notConnected(profile.channel)
      case .loading, nil: if attempt + 1 < pacing.readyAttempts { try await pause() }
      }
    }
    throw ReplyError.notReady(profile.channel)
  }

  func openChat(names: [String]) async throws {
    guard !names.isEmpty else { throw ReplyError.chatNotFound }
    let args: [String: WebArgument] = ["names": .strings(names)]
    switch try await run(profile.openChat, args).string {
    case "open": return
    case "clicked": if try await waitForChat(args) { return }
    default: break
    }
    guard try await run(profile.search, args).string == "typed" else { throw ReplyError.chatNotFound }
    for _ in 0..<pacing.chatAttempts {
      try await pause()
      let result = try await run(profile.openChat, args).string
      if result == "open" { return }
      if result == "clicked", try await waitForChat(args) { return }
    }
    throw ReplyError.chatNotFound
  }

  private func waitForChat(_ args: [String: WebArgument]) async throws -> Bool {
    for _ in 0..<pacing.chatAttempts {
      if try await run(profile.activeChat, args).bool { return true }
      try await pause()
    }
    return false
  }

  func compose(_ text: String) async throws {
    guard try await run(profile.compose, ["text": .string(text)]).string == "ok" else {
      throw ReplyError.composerMissing
    }
  }

  /// Returns how many outgoing messages the chat showed before sending.
  func pressSend() async throws -> Double {
    let before = try await run(profile.send).number ?? -1
    guard before >= 0 else { throw ReplyError.sendButtonMissing }
    return before
  }

  func confirm(text: String, before: Double) async throws {
    let args: [String: WebArgument] = ["text": .string(text), "before": .number(before)]
    for _ in 0..<pacing.confirmAttempts {
      if try await run(profile.confirm, args).string == "sent" { return }
      try await pause()
    }
    throw ReplyError.unconfirmed
  }

  // MARK: Plumbing

  private func pause() async throws {
    try Task.checkCancellation()
    try? await Task.sleep(for: pacing.interval)
  }

  /// Runs a script with a hard timeout. Script exceptions become `.failed`.
  func run(_ script: WebScript, _ arguments: [String: WebArgument] = [:]) async throws -> WebValue {
    let driver = driver
    do {
      return try await ReplyTimeout.run(limit: pacing.scriptTimeout) {
        try await driver.run(script, arguments: arguments)
      }
    } catch let error as ReplyError {
      throw error
    } catch {
      throw ReplyError.failed
    }
  }
}

/// Races main-actor work against a deadline. WebKit calls cannot be cancelled, so the loser's
/// result is simply ignored.
@MainActor
enum ReplyTimeout {
  private final class Gate {
    var open = true
    var timer: Task<Void, Never>?
  }

  static func run<T: Sendable>(limit: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      let gate = Gate()
      let worker = Task { @MainActor in
        let result: Result<T, Error>
        do { result = .success(try await work()) } catch { result = .failure(error) }
        guard gate.open else { return }
        gate.open = false
        gate.timer?.cancel()
        continuation.resume(with: result)
      }
      gate.timer = Task { @MainActor in
        try? await Task.sleep(for: limit)
        guard gate.open, !Task.isCancelled else { return }
        gate.open = false
        worker.cancel()
        continuation.resume(throwing: ReplyError.timeout)
      }
    }
  }
}
