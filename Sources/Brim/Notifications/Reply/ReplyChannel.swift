// ReplyChannel.swift
// Brim
//
// Which app a notification came from decides how the island replies to it: Messages through
// AppleScript, WhatsApp and Telegram through a hidden, signed-in web session. Pure policy, so
// routing and the "which chat is this?" guess are unit-testable.

import Foundation

enum ReplyChannel: String, CaseIterable, Sendable {
  case messages, whatsApp, telegram

  static let whatsAppBundleIDs: Set<String> = [
    "net.whatsapp.whatsapp", "net.whatsapp.whatsappsmb", "desktop.whatsapp", "whatsapp",
  ]
  static let telegramBundleIDs: Set<String> = [
    "ru.keepcoder.telegram", "org.telegram.desktop", "com.tdesktop.telegram",
  ]

  /// The channel for a notification, from its bundle id or, when that is unknown, its app name.
  static func route(bundleID: String?, appName: String) -> ReplyChannel? {
    if let id = bundleID?.lowercased() {
      if id == NotificationApps.messages.lowercased() { return .messages }
      if whatsAppBundleIDs.contains(id) { return .whatsApp }
      if telegramBundleIDs.contains(id) { return .telegram }
      return nil
    }
    switch appName.lowercased() {
    case "messages": return .messages
    case "whatsapp", "whatsapp business": return .whatsApp
    case "telegram", "telegram desktop": return .telegram
    default: return nil
    }
  }

  /// Web channels need the user to link a device first; Messages works out of the box.
  var needsConnection: Bool { self != .messages }

  /// Placeholder of the reply field, as the user's screenshot shows it.
  var placeholder: String {
    switch self {
    case .messages: return L10n.tr("iMessage…")
    case .whatsApp: return L10n.tr("WhatsApp…")
    case .telegram: return L10n.tr("Telegram…")
    }
  }
}

// MARK: - Availability

/// Which web channels are linked. Persisted so `NotificationContent.supportsReply` stays a cheap,
/// thread-safe read; the web sessions update it as their login state changes.
enum ReplyAvailability {
  nonisolated(unsafe) static var defaults: UserDefaults = .standard

  private static func key(_ channel: ReplyChannel) -> String { "replyConnected.\(channel.rawValue)" }

  static func isConnected(_ channel: ReplyChannel) -> Bool {
    !channel.needsConnection || defaults.bool(forKey: key(channel))
  }

  static func setConnected(_ value: Bool, for channel: ReplyChannel) {
    guard channel.needsConnection else { return }
    defaults.set(value, forKey: key(channel))
  }

  static var connected: Set<ReplyChannel> { Set(ReplyChannel.allCases.filter(isConnected)) }
}

// MARK: - Chat names

/// The names a notification might use for its chat, most likely first. WhatsApp and Telegram
/// title a direct chat with the contact; groups show up as "Sender @ Group", or as the group in
/// the title with the sender in the subtitle.
enum ReplyChatNames {
  static func candidates(title: String, subtitle: String) -> [String] {
    var names: [String] = []
    func add(_ raw: String) {
      let name = clean(raw)
      if !name.isEmpty, !names.contains(name) { names.append(name) }
    }
    if let at = title.range(of: " @ ") {
      add(String(title[at.upperBound...]))
      add(String(title[..<at.lowerBound]))
    }
    add(title)
    add(subtitle)
    return names
  }

  /// Strips WhatsApp's "~" marker for people not in the address book and invisible formatting.
  static func clean(_ raw: String) -> String {
    let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{2060}\u{FEFF}")
    var text = String(raw.unicodeScalars.filter { !invisible.contains($0) })
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("~") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
    return text
  }
}
