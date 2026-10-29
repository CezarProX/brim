// ReplyLinker.swift
// Brim
//
// Drives one "Link WhatsApp/Telegram" panel: polls the hidden page about once a second, shows
// the live QR code (it refreshes as the site rotates it), notices the scan, and reports success.
// Used by the island card, Settings and the onboarding page alike.

import Foundation

@MainActor
final class ReplyLinker: ObservableObject {
  @Published private(set) var phase: LinkPhase = .loadingCode

  let session: LinkableSession
  var channel: ReplyChannel { session.channel }
  /// Called once, after the success state has shown for `successHold`.
  var onLinked: (() -> Void)?
  var pollInterval: Duration = .seconds(1)
  var successHold: Duration = .milliseconds(1100)

  private var task: Task<Void, Never>?
  private var codelessPolls = 0

  init(session: LinkableSession) { self.session = session }

  var isRunning: Bool { task != nil }

  func start() {
    guard task == nil else { return }
    if session.isLinked, session.isReady {
      phase = .success
      return
    }
    session.activate()
    task = Task { [weak self] in await self?.run() }
  }

  func stop() {
    task?.cancel()
    task = nil
  }

  /// Reloads the site and starts over, after a failure.
  func retry() {
    stop()
    codelessPolls = 0
    phase = .loadingCode
    session.reload()
    start()
  }

  private func run() async {
    while !Task.isCancelled {
      let snapshot = await session.linkSnapshot()
      guard !Task.isCancelled else { return }
      codelessPolls = snapshot.code == nil ? codelessPolls + 1 : 0
      let next = LinkPhase.next(after: phase, snapshot: snapshot, codelessPolls: codelessPolls)
      if next != phase { phase = next }
      if next.isFinished { break }
      try? await Task.sleep(for: pollInterval)
    }
    guard !Task.isCancelled else { return }  // stop() already cleared `task`; a retry may own it now
    task = nil
    guard phase == .success else { return }
    try? await Task.sleep(for: successHold)
    onLinked?()
  }
}
