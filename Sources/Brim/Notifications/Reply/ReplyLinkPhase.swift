// ReplyLinkPhase.swift
// Brim
//
// What the inline "Link WhatsApp to reply" panel shows, and how it moves from one state to the
// next as the hidden page is polled. Pure values, so the whole linking flow is unit-testable.

import Foundation

/// The QR code the site shows: the payload string when the page exposes it, or the drawn image.
enum LinkCode: Equatable, Sendable {
  case payload(String)
  case image(Data)
}

/// One poll of the hidden page while linking.
struct LinkSnapshot: Equatable, Sendable {
  var status: WebPageStatus
  var code: LinkCode?
  /// Telegram asks for the account's cloud password after the scan; that needs the full page.
  var needsPassword = false
}

enum LinkFailure: Equatable, Sendable {
  case noCode, unsupported, needsPassword
}

enum LinkPhase: Equatable, Sendable {
  /// The page is still loading its code.
  case loadingCode
  case code(LinkCode)
  /// The phone scanned the code; the site is signing in and loading chats.
  case linking
  case success
  case failed(LinkFailure)

  var isFinished: Bool {
    switch self {
    case .success, .failed: return true
    default: return false
    }
  }

  /// Polls of `loadingCode` (about one a second) before giving up on the code.
  static let codeTimeoutPolls = 45

  /// The next phase after a poll. `codelessPolls` counts consecutive polls with no code yet.
  static func next(after current: LinkPhase, snapshot: LinkSnapshot, codelessPolls: Int) -> LinkPhase {
    if snapshot.needsPassword { return .failed(.needsPassword) }
    switch snapshot.status {
    case .connected: return .success
    case .unsupported: return .failed(.unsupported)
    case .login:
      if let code = snapshot.code { return .code(code) }
      if case .code = current { return current }  // the code is rotating; keep showing the last one
      return codelessPolls >= codeTimeoutPolls ? .failed(.noCode) : .loadingCode
    case .loading:
      switch current {
      case .code, .linking: return .linking
      default: return codelessPolls >= codeTimeoutPolls ? .failed(.noCode) : .loadingCode
      }
    }
  }
}

/// Outcome of waiting for a linked session to finish loading.
enum SessionReadiness: Equatable, Sendable {
  case ready, needsLogin, notReady
}
