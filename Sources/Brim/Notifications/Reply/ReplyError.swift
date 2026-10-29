// ReplyError.swift
// Brim
//
// Every way an inline reply can fail, with the short message the card shows under the field.
// Messages never carry the reply text or the chat name, so nothing private ends up in logs.

import Foundation

enum ReplyError: Error, Equatable, Sendable {
  case empty
  case notConnected(ReplyChannel)
  case notReady(ReplyChannel)
  case busy
  case chatNotFound
  case composerMissing
  case sendButtonMissing
  case unconfirmed
  case timeout
  case messagesAutomationDenied
  case messagesConversationMissing
  case failed

  var message: String {
    switch self {
    case .empty: return L10n.tr("Nothing to send")
    case .notConnected(.telegram): return L10n.tr("Connect Telegram in Settings to reply")
    case .notConnected: return L10n.tr("Connect WhatsApp in Settings to reply")
    case .notReady(.telegram): return L10n.tr("Telegram Web is still loading. Try again in a moment.")
    case .notReady: return L10n.tr("WhatsApp Web is still loading. Try again in a moment.")
    case .busy: return L10n.tr("Another reply is sending. Try again.")
    case .chatNotFound: return L10n.tr("Couldn't find this chat")
    case .composerMissing: return L10n.tr("Couldn't type the reply")
    case .sendButtonMissing: return L10n.tr("Couldn't press Send")
    case .unconfirmed: return L10n.tr("Couldn't confirm the reply was sent")
    case .timeout: return L10n.tr("Timed out. Try again.")
    case .messagesAutomationDenied: return L10n.tr("Allow Brim to control Messages in System Settings")
    case .messagesConversationMissing: return L10n.tr("Couldn't find that conversation")
    case .failed: return L10n.tr("Couldn't send the reply")
    }
  }

  /// Maps an osascript failure from `MessagesReply` to a user-facing error.
  static func fromMessages(_ failure: MessagesReply.Failure) -> ReplyError {
    switch failure {
    case .empty: return .empty
    case .scriptFailed(let detail):
      if detail.contains("-1743") { return .messagesAutomationDenied }
      if detail.contains("No conversation") { return .messagesConversationMissing }
      return .failed
    }
  }
}
