// NotificationContent.swift
// Brim
//
// The value types and pure policies behind "notifications in the island":
// the captured content, the 2-second de-duplicator, the pending queue and the
// per-app allow/deny filter. No AppKit here, so all of it is unit-testable.

import Foundation

struct NotificationContent: Identifiable, Equatable, Sendable {
  let id: UUID
  var bundleID: String?
  var appName: String
  var title: String
  var subtitle: String
  var body: String
  var date: Date

  init(id: UUID = UUID(), bundleID: String? = nil, appName: String, title: String = "",
       subtitle: String = "", body: String = "", date: Date = Date()) {
    self.id = id
    self.bundleID = bundleID
    self.appName = appName
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.date = date
  }

  /// Identity used for de-duplication; ignores id and date.
  var fingerprint: String {
    [appName, title, subtitle, body].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\u{1F}")
  }

  var isEmpty: Bool { title.isEmpty && subtitle.isEmpty && body.isEmpty }

  /// How a reply to this notification would be sent, if its app has an inline reply at all.
  var replyChannel: ReplyChannel? { ReplyChannel.route(bundleID: bundleID, appName: appName) }

  /// Messages, WhatsApp and Telegram show a reply bar. WhatsApp and Telegram need linking once;
  /// the card does that in place when the user sends (see ReplyCoordinator).
  var supportsReply: Bool { !title.isEmpty && replyChannel != nil }
}

enum NotificationApps {
  static let messages = "com.apple.MobileSMS"
  static let notificationCenter = "com.apple.notificationcenterui"
}

// MARK: - Dedupe

/// Drops a notification identical to one seen within `window` seconds. The same banner is
/// often observed twice (window-created and element-created, or AX plus the usernoted DB).
struct NotificationDeduper {
  var window: TimeInterval = 2
  private var seen: [String: Date] = [:]

  init(window: TimeInterval = 2) { self.window = window }

  /// True if `content` is new. Records it.
  mutating func accept(_ content: NotificationContent, now: Date = Date()) -> Bool {
    seen = seen.filter { now.timeIntervalSince($0.value) < window }
    let key = content.fingerprint
    if seen[key] != nil { return false }
    seen[key] = now
    return true
  }
}

// MARK: - Queue

/// The card on screen plus those waiting behind it. Value type: every operation returns a new queue.
struct NotificationQueue: Equatable {
  static let maxPending = 8
  private(set) var current: NotificationContent?
  private(set) var pending: [NotificationContent] = []

  /// Number shown in the "+N" badge.
  var overflow: Int { pending.count }

  func enqueued(_ item: NotificationContent) -> NotificationQueue {
    var next = self
    guard current != nil else { next.current = item; return next }
    next.pending.append(item)
    if next.pending.count > Self.maxPending { next.pending.removeFirst(next.pending.count - Self.maxPending) }
    return next
  }

  /// Removes the current card and promotes the next.
  func dismissed() -> NotificationQueue {
    var next = self
    next.current = pending.first
    next.pending = Array(pending.dropFirst())
    return next
  }

  func cleared() -> NotificationQueue { NotificationQueue() }
}

// MARK: - Filter

struct NotificationFilter: Equatable {
  /// Lower-cased bundle ids or app names. Denied wins over allowed.
  var denied: Set<String> = []
  /// Empty means "every app".
  var allowed: Set<String> = []

  init(denied: [String] = [], allowed: [String] = []) {
    self.denied = Set(denied.map { $0.lowercased() })
    self.allowed = Set(allowed.map { $0.lowercased() })
  }

  func permits(bundleID: String?, appName: String) -> Bool {
    let keys = [bundleID?.lowercased(), appName.lowercased()].compactMap { $0 }
    if keys.contains(where: denied.contains) { return false }
    return allowed.isEmpty || keys.contains(where: allowed.contains)
  }
}

// MARK: - Relative time

enum NotificationTimeLabel {
  static func text(for date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m ago"
    case ..<86400: return "\(Int(seconds / 3600))h ago"
    default: return "\(Int(seconds / 86400))d ago"
    }
  }
}
