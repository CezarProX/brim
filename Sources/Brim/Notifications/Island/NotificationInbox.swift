// NotificationInbox.swift
// Brim
//
// The Messages page's data: recent chat notifications (Messages, WhatsApp, Telegram) grouped by
// app and sender, newest first, with an unread count per conversation and a thread of what they
// sent plus the replies sent from the island. Kept in memory only, so nothing a notification said
// outlives the app. Value type: every operation returns a new inbox.

import Foundation

/// One bubble in a conversation's thread.
struct InboxMessage: Identifiable, Equatable, Sendable {
  let id: UUID
  let text: String
  let date: Date
  /// A reply sent from the island, rather than a message received.
  let fromMe: Bool

  init(id: UUID = UUID(), text: String, date: Date, fromMe: Bool) {
    self.id = id
    self.text = text
    self.date = date
    self.fromMe = fromMe
  }
}

struct InboxConversation: Identifiable, Equatable, Sendable {
  static let threadCapacity = 50

  /// App plus sender, so the same name in two apps stays two conversations.
  let id: String
  /// The newest notification received; replies go to it.
  var latest: NotificationContent
  var unread: Int
  /// Oldest first.
  var messages: [InboxMessage] = []

  /// The thread's last bubble, whoever sent it, for the list row.
  var preview: String { messages.last?.text ?? latest.body }

  func appending(_ message: InboxMessage) -> InboxConversation {
    var next = self
    next.messages.append(message)
    if next.messages.count > Self.threadCapacity { next.messages.removeFirst(next.messages.count - Self.threadCapacity) }
    return next
  }

  var sender: String { latest.title }
  var initials: String { Self.initials(for: sender) }

  static func key(for content: NotificationContent) -> String {
    let app = (content.bundleID ?? content.appName).lowercased()
    return [app, content.title, content.subtitle].joined(separator: "\u{1F}")
  }

  /// "Mia Chen" → "MC", "Ana Maria Popescu" → "AP"; a phone number gets "#".
  static func initials(for name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    guard let first = words.first?.first else { return "?" }
    guard first.isLetter else { return "#" }
    let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
    return (String(first) + last).uppercased()
  }
}

struct NotificationInbox: Equatable, Sendable {
  static let capacity = 20

  private(set) var conversations: [InboxConversation] = []

  var unreadTotal: Int { conversations.reduce(0) { $0 + $1.unread } }
  var isEmpty: Bool { conversations.isEmpty }

  /// Adds a chat notification on top. Anything without an inline reply or a sender is ignored.
  func recording(_ content: NotificationContent) -> NotificationInbox {
    guard content.supportsReply else { return self }
    let key = InboxConversation.key(for: content)
    var next = self
    let previous = next.conversations.first { $0.id == key }
    next.conversations.removeAll { $0.id == key }
    let text = content.body.isEmpty ? content.subtitle : content.body
    let updated = InboxConversation(
      id: key, latest: content, unread: (previous?.unread ?? 0) + 1, messages: previous?.messages ?? [])
      .appending(InboxMessage(id: content.id, text: text, date: content.date, fromMe: false))
    next.conversations.insert(updated, at: 0)
    if next.conversations.count > Self.capacity { next.conversations.removeLast(next.conversations.count - Self.capacity) }
    return next
  }

  /// Adds a reply that went out to the conversation `key`, moves it on top and marks it read.
  /// Dropped when that conversation was removed meanwhile.
  func recordingReply(_ text: String, to key: InboxConversation.ID, at date: Date = Date()) -> NotificationInbox {
    guard var conversation = conversations.first(where: { $0.id == key }) else { return self }
    conversation = conversation.appending(InboxMessage(text: text, date: date, fromMe: true))
    conversation.unread = 0
    var next = self
    next.conversations.removeAll { $0.id == key }
    next.conversations.insert(conversation, at: 0)
    return next
  }

  func markingRead(_ id: InboxConversation.ID) -> NotificationInbox {
    var next = self
    next.conversations = conversations.map { conversation in
      var copy = conversation
      if copy.id == id { copy.unread = 0 }
      return copy
    }
    return next
  }

  func removing(_ id: InboxConversation.ID) -> NotificationInbox {
    var next = self
    next.conversations.removeAll { $0.id == id }
    return next
  }

  func cleared() -> NotificationInbox { NotificationInbox() }
}
