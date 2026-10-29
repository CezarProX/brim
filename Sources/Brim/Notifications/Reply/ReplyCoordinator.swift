// ReplyCoordinator.swift
// Brim
//
// The island card's reply brain. Keeps each card's draft, sends through Messages or a web
// session, and when WhatsApp/Telegram is not linked (or was signed out) opens the inline link
// panel instead of failing: the draft is held and sent automatically once the phone scans the
// code. Cancelling the panel keeps the draft. A linked page that is still loading shows
// "Connecting…" and sends when ready.

import Foundation

enum InlineReplyState: Equatable, Sendable {
  case idle
  /// A linked web session is still loading; the reply goes out when it is ready.
  case connecting
  case sending
  case sent
  case failed(String)

  var isBusy: Bool { self == .connecting || self == .sending }
}

/// While true the open island must not collapse on hover exit, and the card must not time out.
enum ReplyHoldPolicy {
  static func holdsIslandOpen(state: InlineReplyState, linking: Bool) -> Bool { linking || state.isBusy }
}

@MainActor
final class ReplyCoordinator: ObservableObject {
  @Published private(set) var state: InlineReplyState = .idle
  /// Non-nil while the link panel is showing.
  @Published private(set) var linker: ReplyLinker?
  @Published var drafts: [UUID: String] = [:]

  /// Called after a reply went out, with the card it belonged to.
  var onSent: (UUID) -> Void = { _ in }
  var readyTimeout: Duration = .seconds(45)

  private var messages: ReplyTransport
  /// The real Messages transport while the filmed demo (`--demo`) sends nowhere.
  private var demoOriginal: ReplyTransport?
  private let sessions: (ReplyChannel) -> LinkableSession?
  private let makeLinker: (LinkableSession) -> ReplyLinker
  private(set) var pending: (text: String, item: NotificationContent)?

  init(messages: ReplyTransport? = nil,
       sessions: ((ReplyChannel) -> LinkableSession?)? = nil,
       makeLinker: ((LinkableSession) -> ReplyLinker)? = nil) {
    self.messages = messages ?? MessagesTransport()
    self.sessions = sessions ?? { WebMessengers.session(for: $0) }
    self.makeLinker = makeLinker ?? { ReplyLinker(session: $0) }
  }

  var holdsIslandOpen: Bool { ReplyHoldPolicy.holdsIslandOpen(state: state, linking: linker != nil) }
  var linkingItemID: UUID? { linker == nil ? nil : pending?.item.id }

  // MARK: Intents

  /// The reply field got focus: start an unlinked page early so its code is ready sooner.
  func prepare(for item: NotificationContent) {
    guard let channel = item.replyChannel, channel.needsConnection else { return }
    sessions(channel)?.activate()
  }

  func send(_ text: String, to item: NotificationContent) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !state.isBusy, linker == nil else { return }
    drafts[item.id] = text
    // Show progress at once when the reply can go straight out; otherwise `deliver` decides
    // between "Connecting…" and the link panel.
    if let channel = item.replyChannel, !channel.needsConnection || sessions(channel)?.isReady == true {
      state = .sending
    }
    Task { await deliver(trimmed, to: item, afterLink: false) }
  }

  /// Esc or the close button: hide the panel, keep the draft.
  func cancelLink() {
    linker?.stop()
    linker = nil
    pending = nil
    state = .idle
  }

  /// The card went away (dismissed or replaced).
  func cardClosed(_ id: UUID) {
    if pending?.item.id == id { cancelLink() }
    drafts[id] = nil
    if !state.isBusy { state = .idle }
    for channel in ReplyChannel.allCases where channel.needsConnection { sessions(channel)?.suspend() }
  }

  func resetState() { if !state.isBusy, linker == nil { state = .idle } }

  /// The filmed demo: replies go to `transport` (nil puts the real Messages transport back).
  func useDemoTransport(_ transport: ReplyTransport?) {
    if let transport {
      if demoOriginal == nil { demoOriginal = messages }
      messages = transport
    } else if let original = demoOriginal {
      messages = original
      demoOriginal = nil
    }
  }

  // MARK: Delivery

  func deliver(_ text: String, to item: NotificationContent, afterLink: Bool) async {
    guard let channel = item.replyChannel else { return finish(.failure(.failed), item) }
    guard channel.needsConnection else {
      state = .sending
      return finish(await messages.send(text, to: item), item)
    }
    guard let session = sessions(channel) else { return finish(.failure(.failed), item) }
    session.activate()
    guard session.isLinked else { return openLink(text, item, session) }
    if !session.isReady {
      state = .connecting
      switch await session.waitUntilReady(timeout: readyTimeout) {
      case .ready: break
      case .needsLogin: return openLink(text, item, session)
      case .notReady: return finish(.failure(.notReady(channel)), item)
      }
    }
    state = .sending
    let names = ReplyChatNames.candidates(title: item.title, subtitle: item.subtitle)
    let result = await session.send(text, names: names, afterLink: afterLink)
    if case .failure(.notConnected) = result { return openLink(text, item, session) }
    finish(result, item)
  }

  private func openLink(_ text: String, _ item: NotificationContent, _ session: LinkableSession) {
    state = .idle
    pending = (text, item)
    let panel = makeLinker(session)
    panel.onLinked = { [weak self] in self?.linked() }
    linker = panel
    panel.start()
  }

  private func linked() {
    guard let pending else { return }
    linker?.stop()
    linker = nil
    self.pending = nil
    state = .sending
    Task { await deliver(pending.text, to: pending.item, afterLink: true) }
  }

  private func finish(_ result: Result<Void, ReplyError>, _ item: NotificationContent) {
    switch result {
    case .success:
      state = .sent
      drafts[item.id] = nil
      onSent(item.id)
    case .failure(let error):
      state = .failed(error.message)
    }
  }
}
