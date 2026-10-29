// NotificationHUDModel.swift
// Brim
//
// Owns the notification card shown in the island: capture sources, filtering, de-duplication,
// the queue and the auto-dismiss timer. The shell observes `current` and `overflow`.

import AppKit
import Combine

@MainActor
final class NotificationHUDModel: ObservableObject {
  static let shared = NotificationHUDModel()

  @Published private(set) var queue = NotificationQueue()
  @Published private(set) var needsAccessibility = false
  /// Recent chats for the Messages page; survives the card's dismissal, not a relaunch.
  @Published private(set) var inbox = NotificationInbox()
  /// The Messages page row whose reply bar is open.
  @Published private(set) var openConversation: InboxConversation.ID?
  /// Drafts, sending and the inline link panel for the card's reply bar.
  let replies: ReplyCoordinator

  typealias ReplyState = InlineReplyState
  var replyState: ReplyState { replies.state }

  var current: NotificationContent? { queue.current }
  var overflow: Int { queue.overflow }

  private var deduper = NotificationDeduper()
  private let observer = NotificationBannerObserver()
  private let usernoted = UsernotedReader()
  private var pollTimer: Timer?
  /// Polls for Accessibility while the feature is on but not yet trusted, so it starts the moment
  /// the user allows Brim in System Settings instead of after a relaunch.
  private var trustTimer: Timer?
  private let trust: TrustAccess
  private var dismissTask: Task<Void, Never>?
  private var paused = false
  private let settings: AppSettings
  private var replyWatch: AnyCancellable?
  private var heldByReply = false
  /// Replies on their way, by the notification they answer, so the thread shows them once sent.
  private var outgoing: [UUID: (conversation: InboxConversation.ID, text: String)] = [:]

  /// How the model checks and asks for Accessibility; injectable so tests never prompt.
  struct TrustAccess {
    var isTrusted: @MainActor () -> Bool = { NotificationBannerObserver.isTrusted }
    var request: @MainActor () -> Void = { NotificationBannerObserver.requestTrust() }
  }

  init(settings: AppSettings = .shared, replies: ReplyCoordinator? = nil, trust: TrustAccess = TrustAccess()) {
    self.settings = settings
    self.trust = trust
    self.replies = replies ?? ReplyCoordinator()
    self.replies.onSent = { [weak self] id in self?.replySent(id) }
    replyWatch = self.replies.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
      Task { @MainActor [weak self] in self?.syncReplyHold() }
    }
  }

  /// The island stays open (no hover collapse, no timeout) while this is true.
  var holdsIslandOpen: Bool { current != nil && replies.holdsIslandOpen }

  /// Height of the open card below the notch, for the island's geometry.
  var cardBodyHeight: CGFloat {
    NotificationCardMetrics.bodyHeight(
      supportsReply: current?.supportsReply == true,
      linking: current != nil && replies.linkingItemID == current?.id)
  }

  // MARK: Lifecycle

  /// Call at launch and whenever a notification setting changes.
  func start() {
    stop()
    guard settings.notificationHUDEnabled else { return }
    WebMessengers.warmUp()
    observer.hidesBanner = settings.notificationHUDHideBanner
    observer.onContent = { [weak self] in self?.ingest($0) }
    needsAccessibility = !trust.isTrusted()
    if needsAccessibility {
      trust.request()
      trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.checkTrust() }
      }
    } else {
      observer.start()
    }
    if settings.notificationHUDUsernotedFallback, UsernotedReader.isReadable { startPolling() }
  }

  /// Starts reading banners once Accessibility has been granted.
  func checkTrust() {
    guard needsAccessibility, trust.isTrusted() else { return }
    needsAccessibility = false
    trustTimer?.invalidate()
    trustTimer = nil
    observer.start()
  }

  func stop() {
    observer.stop()
    trustTimer?.invalidate()
    trustTimer = nil
    pollTimer?.invalidate()
    pollTimer = nil
    dismissTask?.cancel()
    queue = queue.cleared()
  }

  private func startPolling() {
    _ = usernoted.newContent()  // records the high-water mark
    pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        for var item in self.usernoted.newContent() {
          if let id = item.bundleID { item.appName = NotificationAppResolver.shared.displayName(forBundleID: id) }
          self.ingest(item)
        }
      }
    }
  }

  // MARK: Intake

  func ingest(_ content: NotificationContent, now: Date = Date()) {
    guard settings.notificationHUDEnabled, !content.isEmpty,
      NotificationFilter(denied: settings.notificationHUDDeniedApps, allowed: settings.notificationHUDAllowedApps)
        .permits(bundleID: content.bundleID, appName: content.appName),
      !(settings.notificationHUDHideWhileSharing && ScreenSharingProbe.isSharing),
      deduper.accept(content, now: now)
    else { return }
    var shown = content
    if !settings.notificationHUDShowBody { shown.body = "" }
    let wasEmpty = queue.current == nil
    queue = queue.enqueued(shown)
    inbox = inbox.recording(shown)
    if let open = openConversation, open == InboxConversation.key(for: shown) { markRead(open) }
    if wasEmpty { replies.resetState(); scheduleDismiss() }
  }

  // MARK: User actions

  func dismiss() {
    if let id = queue.current?.id { replies.cardClosed(id) }
    queue = queue.dismissed()
    paused = false
    scheduleDismiss()
  }

  func open(_ item: NotificationContent) {
    if let id = item.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    dismiss()
  }

  /// Hovering or typing in the card holds it open.
  func setPaused(_ value: Bool) {
    paused = value
    value ? dismissTask?.cancel() : scheduleDismiss()
  }

  func reply(_ text: String, to item: NotificationContent) {
    guard item.supportsReply else { return }
    outgoing[item.id] = (InboxConversation.key(for: item), text.trimmingCharacters(in: .whitespacesAndNewlines))
    replies.send(text, to: item)
  }

  func replyFieldFocused(_ item: NotificationContent) { replies.prepare(for: item) }

  // MARK: Messages page

  /// Replies to the conversation's newest message and marks it read.
  func reply(_ text: String, in conversation: InboxConversation) {
    reply(text, to: conversation.latest)
    markRead(conversation.id)
  }

  /// A row click opens its reply bar (closing any other) and marks it read; a second click closes it.
  func toggleConversation(_ conversation: InboxConversation) {
    openConversation = openConversation == conversation.id ? nil : conversation.id
    markRead(conversation.id)
  }

  func openApp(for conversation: InboxConversation) {
    if let id = conversation.latest.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    markRead(conversation.id)
  }

  func markRead(_ id: InboxConversation.ID) { inbox = inbox.markingRead(id) }

  func removeConversation(_ id: InboxConversation.ID) {
    inbox = inbox.removing(id)
    if openConversation == id { openConversation = nil }
  }

  func clearInbox() {
    inbox = inbox.cleared()
    openConversation = nil
  }

  /// Height of the Messages page below the camera band, for the island's geometry.
  var inboxPageHeight: CGFloat {
    let open = inbox.conversations.first { $0.id == openConversation }
    return NotificationInboxLayout.height(
      count: inbox.conversations.count, threadOpen: open != nil,
      linking: open != nil && replies.linkingItemID == open?.latest.id)
  }

  private func replySent(_ id: UUID) {
    if let sent = outgoing.removeValue(forKey: id) {
      inbox = inbox.recordingReply(sent.text, to: sent.conversation)
    }
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      guard let self else { return }
      // The open thread stays, ready for the next reply; a reply from the card closes the card.
      if self.openConversation != nil { self.replies.resetState() }
      guard self.queue.current?.id == id else { return }
      self.dismiss()
    }
  }

  /// Linking or sending holds the card: no auto-dismiss until it is done.
  private func syncReplyHold() {
    let hold = replies.holdsIslandOpen
    guard hold != heldByReply else { return }
    heldByReply = hold
    hold ? dismissTask?.cancel() : scheduleDismiss()
  }

  // MARK: Auto-dismiss

  private func scheduleDismiss() {
    dismissTask?.cancel()
    guard queue.current != nil, !paused, !heldByReply else { return }
    let seconds = settings.notificationHUDDuration
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }
}

/// Best-effort screen-sharing detection. macOS has no public "someone is sharing" API, so this
/// checks for mirrored displays and for the floating controls of common sharing apps.
enum ScreenSharingProbe {
  static var isSharing: Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var count: UInt32 = 0
    if CGGetOnlineDisplayList(8, &ids, &count) == .success, ids.prefix(Int(count)).contains(where: { CGDisplayIsInMirrorSet($0) != 0 }) {
      return true
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
      let name = (window[kCGWindowName as String] as? String)?.lowercased() ?? ""
      return name.contains("share toolbar") || name.contains("screen sharing") || name.contains("sharing indicator")
    }
  }
}

// MARK: Filmed demo

extension NotificationHUDModel {
  /// Shows `content` as if it had just arrived (`--demo` filming). It skips the app filters and the
  /// screen-sharing check, which the filming tool's screen recording would trip, and holds the card.
  func presentForDemo(_ content: NotificationContent) {
    let wasEmpty = queue.current == nil
    queue = queue.enqueued(content)
    inbox = inbox.recording(content)
    if wasEmpty { replies.resetState() }
    setPaused(true)
  }

  /// Swaps the Messages page's chats (the user's real ones while filming); returns what was there.
  func replaceInboxForDemo(with next: NotificationInbox) -> NotificationInbox {
    let previous = inbox
    inbox = next
    openConversation = nil
    return previous
  }
}
