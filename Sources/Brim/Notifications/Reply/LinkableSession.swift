// LinkableSession.swift
// Brim
//
// What the reply coordinator and the link panel need from a web messenger session. The real
// `WebMessengerSession` conforms; tests use a scripted fake.

import Foundation

@MainActor
protocol LinkableSession: AnyObject {
  var channel: ReplyChannel { get }
  /// The user linked this messenger (persisted).
  var isLinked: Bool { get }
  /// The page is loaded and signed in right now.
  var isReady: Bool { get }
  func activate()
  func reload()
  func suspend()
  /// One poll for the link panel: login state plus the current QR code.
  func linkSnapshot() async -> LinkSnapshot
  /// Waits for a linked page to finish loading.
  func waitUntilReady(timeout: Duration) async -> SessionReadiness
  func send(_ text: String, names: [String], afterLink: Bool) async -> Result<Void, ReplyError>
}

extension WebMessengerSession: LinkableSession {
  func linkSnapshot() async -> LinkSnapshot {
    activate()
    guard let status = await refreshStatus() else { return LinkSnapshot(status: .loading) }
    guard status == .login, let driver else { return LinkSnapshot(status: status) }
    let sender = WebReplySender(driver: driver, profile: profile, pacing: pacing)
    let raw = (try? await sender.run(profile.qrCode))?.string ?? ""
    return Self.snapshot(status: status, qrJSON: raw)
  }

  /// Parses the QR script's JSON. Unknown or broken JSON reads as "no code yet".
  nonisolated static func snapshot(status: WebPageStatus, qrJSON: String) -> LinkSnapshot {
    struct Payload: Decodable { var payload: String?; var image: String?; var needsPassword: Bool? }
    let parsed = try? JSONDecoder().decode(Payload.self, from: Data(qrJSON.utf8))
    var snapshot = LinkSnapshot(status: status, needsPassword: parsed?.needsPassword ?? false)
    if let image = parsed?.image.flatMap(ReplyQRImage.data(fromDataURL:)) {
      snapshot.code = .image(image)
    } else if let payload = parsed?.payload, !payload.isEmpty {
      snapshot.code = .payload(payload)
    }
    return snapshot
  }

  func waitUntilReady(timeout: Duration) async -> SessionReadiness {
    activate()
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while true {
      if state == .connected { return .ready }
      await refreshStatus()
      switch state {
      case .connected: return .ready
      case .needsLogin: return .needsLogin
      default: break
      }
      guard clock.now < deadline, !Task.isCancelled else { return .notReady }
      try? await Task.sleep(for: max(pacing.interval, .milliseconds(10)))
    }
  }
}
