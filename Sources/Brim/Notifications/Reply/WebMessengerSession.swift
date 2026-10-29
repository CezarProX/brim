// WebMessengerSession.swift
// Brim
//
// Owns one messenger's hidden web page and its connection state. The page is created lazily
// (when a reply needs it, or at launch if the user linked before) and kept alive while linked.
// Replies are serialized: a second reply while one is in flight fails fast with `.busy`.
// Nothing here logs or stores message text or chat names.

import AppKit

@MainActor
final class WebMessengerSession: ObservableObject {
  enum State: Equatable, Sendable {
    /// No page exists.
    case off
    case loading
    /// The page shows the QR / phone-number login.
    case needsLogin
    case connected
    /// The site refused this browser.
    case unsupported
  }

  @Published private(set) var state: State = .off
  @Published private(set) var isSending = false

  let profile: WebMessengerProfile
  var pacing: ReplyPacing
  /// How often the login state is re-read while linking, and once linked.
  var linkingPoll: Duration = .seconds(2)
  var connectedPoll: Duration = .seconds(30)
  /// Tests drive `refreshStatus()` by hand.
  var pollsAutomatically = true
  /// Consecutive login screens needed before a linked session counts as signed out, so a
  /// reload blip never unlinks it.
  var loggedOutAfter = 2

  private let makeDriver: @MainActor (WebMessengerProfile) -> WebPageDriving
  let link: ReplyLink
  private(set) var driver: WebPageDriving?
  private var pollTask: Task<Void, Never>?
  private var loginStreak = 0

  init(profile: WebMessengerProfile, pacing: ReplyPacing = .standard,
       link: ReplyLink? = nil,
       makeDriver: @escaping @MainActor (WebMessengerProfile) -> WebPageDriving = { WKWebPageDriver(profile: $0) }) {
    self.profile = profile
    self.pacing = pacing
    self.makeDriver = makeDriver
    self.link = link ?? .persisted(profile.channel)
  }

  var channel: ReplyChannel { profile.channel }
  var isLinked: Bool { link.get() }
  var isReady: Bool { state == .connected }

  // MARK: Connection

  /// Creates and loads the page if needed. Idempotent.
  func activate() {
    guard driver == nil else { return }
    let page = makeDriver(profile)
    driver = page
    state = .loading
    page.load(profile.home)
    if pollsAutomatically { startPolling() }
  }

  /// Reloads the site, e.g. to get a fresh code after a failure.
  func reload() {
    guard let driver else { return activate() }
    state = .loading
    driver.load(profile.home)
  }

  /// Drops the page without signing out (used when an unlinked page is no longer needed).
  func suspend() {
    guard !isLinked, let driver else { return }
    pollTask?.cancel()
    pollTask = nil
    driver.tearDown()
    self.driver = nil
    state = .off
  }

  /// Signs out locally: erases this messenger's private data store and drops the page.
  func disconnect() async {
    pollTask?.cancel()
    pollTask = nil
    if let driver {
      await driver.eraseData()
      driver.tearDown()
    }
    driver = nil
    state = .off
    loginStreak = 0
    link.set(false)
  }

  /// Reads the page's login state once and records it.
  @discardableResult
  func refreshStatus() async -> WebPageStatus? {
    guard let driver else { return nil }
    let sender = WebReplySender(driver: driver, profile: profile, pacing: pacing)
    guard let value = try? await sender.run(profile.status) else { return nil }
    let status = WebPageStatus(rawValue: value.string) ?? .loading
    apply(status)
    return status
  }

  func apply(_ status: WebPageStatus) {
    loginStreak = status == .login ? loginStreak + 1 : 0
    switch status {
    case .connected:
      state = .connected
      link.set(true)
    case .login:
      guard !isLinked || loginStreak >= loggedOutAfter else { return }
      state = .needsLogin
      link.set(false)
    case .unsupported: state = .unsupported
    case .loading: if state != .connected { state = .loading }
    }
  }

  private func startPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.refreshStatus()
        let wait = self.state == .connected ? self.connectedPoll : self.linkingPoll
        try? await Task.sleep(for: wait)
      }
    }
  }

  // MARK: Sending

  /// - Parameter afterLink: right after linking the site is still syncing its chat list, so the
  ///   chat search gets much longer to succeed.
  func send(_ text: String, names: [String], afterLink: Bool = false) async -> Result<Void, ReplyError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(.empty) }
    guard !isSending else { return .failure(.busy) }
    if driver == nil {
      guard isLinked || state == .connected else { return .failure(.notConnected(channel)) }
      activate()
    }
    guard let driver else { return .failure(.notConnected(channel)) }
    isSending = true
    defer { isSending = false }
    var steps = pacing
    if afterLink { steps.chatAttempts = max(steps.chatAttempts, 60) }
    do {
      try await WebReplySender(driver: driver, profile: profile, pacing: steps).send(text: trimmed, names: names)
      apply(.connected)
      return .success(())
    } catch let error as ReplyError {
      if error == .notConnected(channel) { forceLoggedOut() }
      return .failure(error)
    } catch {
      return .failure(.failed)
    }
  }

  /// The send flow saw the login screen itself: the session is gone.
  func forceLoggedOut() {
    loginStreak = loggedOutAfter
    state = .needsLogin
    link.set(false)
  }
}

/// Whether the user linked this messenger, persisted across launches.
struct ReplyLink {
  var get: () -> Bool
  var set: (Bool) -> Void

  static func persisted(_ channel: ReplyChannel) -> ReplyLink {
    ReplyLink(get: { ReplyAvailability.isConnected(channel) }, set: { ReplyAvailability.setConnected($0, for: channel) })
  }
}

/// The two web sessions the app keeps.
@MainActor
enum WebMessengers {
  static let whatsApp = WebMessengerSession(profile: .whatsApp)
  static let telegram = WebMessengerSession(profile: .telegram)

  static func session(for channel: ReplyChannel) -> WebMessengerSession? {
    switch channel {
    case .messages: return nil
    case .whatsApp: return whatsApp
    case .telegram: return telegram
    }
  }

  /// Starts the pages the user linked before, so the first reply does not wait for a cold load.
  static func warmUp() {
    for channel in ReplyChannel.allCases where channel.needsConnection && ReplyAvailability.isConnected(channel) {
      session(for: channel)?.activate()
    }
  }
}
