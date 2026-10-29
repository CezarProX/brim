// InboxThreadView.swift
// Brim
//
// One conversation on the Messages page: a header (back, avatar, name, app), the thread as chat
// bubbles (theirs grey on the left, replies sent from the island blue on the right, newest at the
// bottom) and the reply bar. Only what passed through the island is here: messages that arrived as
// notifications and replies sent from Brim, not the app's full history.

import SwiftUI

struct InboxThreadView: View {
  let conversation: InboxConversation
  var replyState: NotificationHUDModel.ReplyState = .idle
  /// Non-nil while WhatsApp or Telegram needs linking; its panel replaces the thread.
  var linker: ReplyLinker?
  var actions = NotificationInboxActions()

  @State private var draft = ""
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      header
      if let linker, let channel = conversation.latest.replyChannel {
        InboxLinkPanel(linker: linker, channel: channel, hasDraft: !draft.isEmpty, cancel: actions.cancelLink)
          .transition(.islandContent)
      } else {
        thread
        if let channel = conversation.latest.replyChannel {
          NotificationReplyBar(channel: channel, text: $draft, replyState: replyState,
                               onSend: { actions.reply($0, conversation) }) { focused in
            if focused { actions.fieldFocused(conversation) }
          }
          .frame(height: NotificationInboxLayout.replyHeight, alignment: .bottom)
        }
      }
    }
    .onChange(of: replyState) { _, state in if state == .sent { draft = "" } }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: linker == nil)
  }

  private var header: some View {
    HStack(spacing: IslandSpace.s) {
      Button { actions.toggle(conversation) } label: {
        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(IslandInk.secondary)
          .frame(width: 28, height: 28)
          .background(IslandFill.subtle, in: Circle())
      }
      .buttonStyle(IslandPressStyle())
      .accessibilityLabel("Back to messages")
      InboxAvatar(conversation: conversation, size: 28)
      VStack(alignment: .leading, spacing: 0) {
        Text(conversation.sender).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        Text(conversation.latest.appName).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      }
      Spacer(minLength: 0)
      Button { actions.open(conversation) } label: {
        Image(systemName: "arrow.up.forward.app").font(.system(size: 13, weight: .medium))
          .foregroundStyle(IslandInk.secondary)
          .frame(width: 28, height: 28)
          .background(IslandFill.subtle, in: Circle())
      }
      .buttonStyle(IslandPressStyle())
      .help("Open \(conversation.latest.appName)")
      .accessibilityLabel("Open \(conversation.latest.appName)")
    }
    .frame(height: NotificationInboxLayout.threadHeaderHeight)
  }

  private var thread: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(conversation.messages) { message in
            InboxBubble(message: message).id(message.id)
          }
        }
        .padding(.vertical, IslandSpace.s)
      }
      .scrollIndicators(.never)
      .defaultScrollAnchor(.bottom)
      .onChange(of: conversation.messages.last?.id) { _, last in
        guard let last else { return }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(last, anchor: .bottom) }
      }
    }
    .frame(height: NotificationInboxLayout.threadBodyHeight)
    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                 .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
  }
}

/// A chat bubble: theirs grey on the left, yours blue on the right.
struct InboxBubble: View {
  let message: InboxMessage

  var body: some View {
    HStack {
      if message.fromMe { Spacer(minLength: 64) }
      Text(message.text)
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .textSelection(.enabled)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(message.fromMe ? NotificationReplyBar.sendBlue : Color(white: 0.2),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      if !message.fromMe { Spacer(minLength: 64) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message.fromMe ? "You: \(message.text)" : message.text)
  }
}
