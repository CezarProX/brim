// NotificationInboxPage.swift
// Brim
//
// The island's Messages page: recent chats from Messages, WhatsApp and Telegram, one row per
// sender with an initials avatar, the app's badge, the last message, time and an unread count.
// Clicking a row opens its thread (InboxThreadView) with the reply bar at the bottom.
// Right-click a row to open the app or remove it; "Clear All" empties the list.

import SwiftUI

/// Sizes of the Messages page below the camera band.
enum NotificationInboxLayout {
  static let rowHeight: CGFloat = 58
  static let visibleRows = 4
  static let replyHeight: CGFloat = 44
  static let topPadding: CGFloat = 6
  static let bottomPadding: CGFloat = 14
  static let emptyHeight: CGFloat = 120
  static let threadHeaderHeight: CGFloat = 44
  static let threadBodyHeight: CGFloat = 220

  static func height(count: Int, threadOpen: Bool, linking: Bool) -> CGFloat {
    if threadOpen {
      let body = linking ? ReplyLinkPanel.height : threadBodyHeight + replyHeight
      return topPadding + threadHeaderHeight + body + bottomPadding
    }
    guard count > 0 else { return emptyHeight }
    return topPadding + CGFloat(min(count, visibleRows)) * rowHeight + bottomPadding
  }
}

/// Bound to the shared model; what the shell embeds on the Messages page.
struct NotificationInboxHost: View {
  @ObservedObject var model: NotificationHUDModel = .shared

  var body: some View {
    NotificationInboxPage(
      conversations: model.inbox.conversations, openID: model.openConversation,
      replyState: model.replyState, linker: model.replies.linkingItemID == nil ? nil : model.replies.linker,
      linkingItemID: model.replies.linkingItemID,
      actions: NotificationInboxActions(
        toggle: { model.toggleConversation($0) },
        reply: { text, conversation in model.reply(text, in: conversation) },
        fieldFocused: { model.replyFieldFocused($0.latest) },
        open: { model.openApp(for: $0) },
        remove: { model.removeConversation($0.id) },
        clearAll: { model.clearInbox() },
        cancelLink: { model.replies.cancelLink() }))
  }
}

struct NotificationInboxActions {
  var toggle: (InboxConversation) -> Void = { _ in }
  var reply: (String, InboxConversation) -> Void = { _, _ in }
  var fieldFocused: (InboxConversation) -> Void = { _ in }
  var open: (InboxConversation) -> Void = { _ in }
  var remove: (InboxConversation) -> Void = { _ in }
  var clearAll: () -> Void = {}
  var cancelLink: () -> Void = {}
}

struct NotificationInboxPage: View {
  let conversations: [InboxConversation]
  var openID: InboxConversation.ID?
  var replyState: NotificationHUDModel.ReplyState = .idle
  var linker: ReplyLinker?
  var linkingItemID: UUID?
  var actions = NotificationInboxActions()
  var now = Date()

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var openConversation: InboxConversation? { conversations.first { $0.id == openID } }

  var body: some View {
    Group {
      if let conversation = openConversation {
        InboxThreadView(
          conversation: conversation, replyState: replyState,
          linker: linkingItemID == conversation.latest.id ? linker : nil, actions: actions)
          .transition(.islandContent)
      } else if conversations.isEmpty {
        empty
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
              if index > 0 { Rectangle().fill(IslandFill.hairline).frame(height: 1).padding(.leading, 64) }
              row(conversation)
            }
          }
        }
        .scrollIndicators(.never)
        .scrollDisabled(conversations.count <= NotificationInboxLayout.visibleRows)
        .transition(.islandContent)
      }
    }
    .padding(.horizontal, IslandSpace.l + IslandPageLayout.openShoulder)
    .padding(.top, NotificationInboxLayout.topPadding)
    .padding(.bottom, NotificationInboxLayout.bottomPadding)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: openID)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: conversations.map(\.id))
  }

  private var empty: some View {
    VStack(spacing: IslandSpace.s) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 22, weight: .medium)).foregroundStyle(IslandInk.tertiary)
      Text("No messages yet").font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
      Text("Messages, WhatsApp and Telegram notifications show up here.")
        .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func row(_ conversation: InboxConversation) -> some View {
    Button { actions.toggle(conversation) } label: { summary(conversation) }
      .buttonStyle(InboxRowStyle())
      .contextMenu {
        Button("Open \(conversation.latest.appName)") { actions.open(conversation) }
        Button("Remove") { actions.remove(conversation) }
        Divider()
        Button("Clear All") { actions.clearAll() }
      }
  }

  private func summary(_ conversation: InboxConversation) -> some View {
    HStack(spacing: IslandSpace.m) {
      InboxAvatar(conversation: conversation)
      VStack(alignment: .leading, spacing: 2) {
        Text(conversation.sender).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        Text(conversation.messages.last?.fromMe == true ? L10n.tr("You: %@", conversation.preview) : conversation.preview)
          .font(IslandFont.body).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: IslandSpace.s) {
        if conversation.unread > 1 { InboxUnreadBadge(count: conversation.unread) }
        Text(NotificationTimeLabel.text(for: conversation.latest.date, now: now))
          .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
      }
    }
    .frame(height: NotificationInboxLayout.rowHeight)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the conversation")
  }
}

/// Initials on a grey disc, with the app's icon in the bottom-right corner.
struct InboxAvatar: View {
  let conversation: InboxConversation
  var size: CGFloat = 40

  var body: some View {
    Circle()
      .fill(LinearGradient(colors: [Color(white: 0.56), Color(white: 0.38)], startPoint: .top, endPoint: .bottom))
      .overlay(Text(conversation.initials).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white))
      .frame(width: size, height: size)
      .overlay(alignment: .bottomTrailing) {
        NotificationAppIcon(content: conversation.latest, size: size * 0.42)
          .padding(1.5)
          .background(Color.black, in: Circle())
          .clipShape(Circle())
          .offset(x: 3, y: 3)
      }
      .accessibilityHidden(true)
  }
}

struct InboxUnreadBadge: View {
  let count: Int

  var body: some View {
    Text("\(min(count, 99))")
      .font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundStyle(.white)
      .frame(minWidth: 18, minHeight: 18)
      .padding(.horizontal, count > 9 ? 4 : 0)
      .background(Color(red: 1, green: 0.27, blue: 0.23), in: Capsule())
      .contentTransition(.numericText())
      .accessibilityLabel("\(count) unread")
  }
}

/// Hover fill for a row, like the system's list highlight.
private struct InboxRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    InboxRowBody(configuration: configuration)
  }

  private struct InboxRowBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false

    var body: some View {
      configuration.label
        .padding(.horizontal, IslandSpace.s)
        .background(
          RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
            .fill(configuration.isPressed ? IslandFill.hover : hovered ? IslandFill.subtle : .clear))
        .padding(.horizontal, -IslandSpace.s)
        .onHover { hovered = $0 }
    }
  }
}

/// The "Link WhatsApp to reply" panel in place of the reply bar, re-rendered on each phase change.
struct InboxLinkPanel: View {
  @ObservedObject var linker: ReplyLinker
  let channel: ReplyChannel
  let hasDraft: Bool
  let cancel: () -> Void

  var body: some View {
    ReplyLinkPanel(
      channel: channel, phase: linker.phase, hasDraft: hasDraft, onClose: cancel,
      onRetry: { linker.retry() },
      onOpenPage: {
        if let session = linker.session as? WebMessengerSession { WebMessengerConnectWindow.show(for: session) }
      })
  }
}
