// MessagesTransport.swift
// Brim
//
// The plain (no-linking) reply transport for Messages. Routing between Messages and the web
// sessions lives in ReplyCoordinator.

import Foundation

@MainActor
protocol ReplyTransport: AnyObject {
  func send(_ text: String, to item: NotificationContent) async -> Result<Void, ReplyError>
}

/// Messages through AppleScript (see MessagesReply).
@MainActor
final class MessagesTransport: ReplyTransport {
  func send(_ text: String, to item: NotificationContent) async -> Result<Void, ReplyError> {
    await withCheckedContinuation { continuation in
      MessagesReply.send(text, to: item.title) { result in
        continuation.resume(returning: result.mapError(ReplyError.fromMessages))
      }
    }
  }
}
