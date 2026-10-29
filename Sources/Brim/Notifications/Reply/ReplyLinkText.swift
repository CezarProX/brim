// ReplyLinkText.swift
// Brim
//
// User-facing text for linking and the web reply sessions, in one place for translation.

import Foundation

enum ReplyLinkText {
  static func title(_ channel: ReplyChannel, phase: LinkPhase, hasDraft: Bool) -> String {
    if phase == .success {
      if hasDraft { return L10n.tr("Linked. Sending your reply…") }
      return channel == .telegram ? L10n.tr("Telegram is linked") : L10n.tr("WhatsApp is linked")
    }
    return channel == .telegram ? L10n.tr("Link Telegram to reply") : L10n.tr("Link WhatsApp to reply")
  }

  static func steps(_ channel: ReplyChannel) -> [String] {
    channel == .telegram
      ? [L10n.tr("Open Telegram on your phone"), L10n.tr("Go to Settings → Devices"),
         L10n.tr("Tap Link Desktop Device and scan this code")]
      : [L10n.tr("Open WhatsApp on your phone"), L10n.tr("Go to Settings → Linked devices"),
         L10n.tr("Tap Link a device and scan this code")]
  }

  static func privacy(_ channel: ReplyChannel) -> String {
    channel == .telegram
      ? L10n.tr("Replies are sent from this Mac through Telegram Web. Nothing leaves your Mac otherwise.")
      : L10n.tr("Replies are sent from this Mac through WhatsApp Web. Nothing leaves your Mac otherwise.")
  }

  static func failure(_ failure: LinkFailure, channel: ReplyChannel) -> String {
    switch failure {
    case .noCode: return L10n.tr("Couldn't load the code. Check your connection and try again.")
    case .unsupported: return L10n.tr("The site refused to load here. Try again later.")
    case .needsPassword: return L10n.tr("Your Telegram account has a cloud password. Enter it in Telegram Web to finish.")
    }
  }
}

/// User-facing text for the web reply sessions.
enum WebMessengerText {
  static func connectTitle(_ channel: ReplyChannel) -> String {
    channel == .telegram ? L10n.tr("Connect Telegram") : L10n.tr("Connect WhatsApp")
  }

  static func instructions(_ channel: ReplyChannel) -> String {
    channel == .telegram
      ? L10n.tr("On your phone, open Telegram, go to Settings > Devices > Link Desktop Device, and scan this code.")
      : L10n.tr("On your phone, open WhatsApp, go to Settings > Linked devices > Link a device, and scan this code.")
  }

  static func status(_ state: WebMessengerSession.State, channel: ReplyChannel) -> String {
    switch state {
    case .off: return L10n.tr("Not connected")
    case .loading: return L10n.tr("Loading…")
    case .needsLogin: return L10n.tr("Waiting for you to scan the code")
    case .unsupported: return L10n.tr("The site refused to load here. Try again later.")
    case .connected:
      return channel == .telegram
        ? L10n.tr("Connected. Replies send through Telegram Web.")
        : L10n.tr("Connected. Replies send through WhatsApp Web.")
    }
  }
}
