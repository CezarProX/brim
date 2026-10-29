// NotificationReplyBar.swift
// Brim
//
// The inline reply row under a notification card (the draft lives in the model): a rounded field with the app's placeholder
// ("iMessage…", "WhatsApp…", "Telegram…"), a blue circular send button and an emoji button that
// opens the system character palette. Return sends. Sending, sent and failed states show in place.
// No paperclip: none of the transports can attach files without driving the app's UI.

import AppKit
import SwiftUI

struct NotificationReplyBar: View {
  let channel: ReplyChannel
  @Binding var text: String
  var replyState: NotificationHUDModel.ReplyState = .idle
  var onSend: (String) -> Void = { _ in }
  var onFocusChange: (Bool) -> Void = { _ in }

  @FocusState private var focused: Bool

  static let sendBlue = Color(red: 0.04, green: 0.52, blue: 1)

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      field
      sendButton
      emojiButton
    }
    .overlay(alignment: .bottomLeading) {
      if let caption {
        Text(verbatim: caption.text).font(IslandFont.caption).foregroundStyle(caption.color).lineLimit(1).offset(y: 16)
      }
    }
    .padding(.bottom, caption == nil ? 0 : 14)
  }

  private var field: some View {
    TextField(channel.placeholder, text: $text)
      .textFieldStyle(.plain).font(IslandFont.body).foregroundStyle(IslandInk.primary)
      .focused($focused)
      .onSubmit(send)
      .onChange(of: focused) { _, value in onFocusChange(value) }
      .disabled(replyState.isBusy)
      .padding(.horizontal, IslandSpace.m).frame(height: 30)
      .background(IslandFill.subtle, in: Capsule())
      .overlay(Capsule().strokeBorder(focused ? IslandFill.selected : IslandFill.hairline, lineWidth: 1))
  }

  private var sendButton: some View {
    Button(action: send) {
      ZStack {
        Circle().fill(canSend || replyState == .sent ? Self.sendBlue : IslandFill.selected)
        switch replyState {
        case .sending, .connecting: ProgressView().controlSize(.mini).tint(.white)
        case .sent: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
        default: Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
        }
      }
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
    }
    .buttonStyle(IslandPressStyle())
    .disabled(!canSend && replyState != .sent)
    .accessibilityLabel("Send reply")
  }

  private var emojiButton: some View {
    Button(action: openEmojiPalette) {
      Image(systemName: "face.smiling").font(.system(size: 15, weight: .medium))
        .foregroundStyle(IslandInk.secondary)
        .frame(width: 28, height: 28)
        .background(IslandFill.subtle, in: Circle())
    }
    .buttonStyle(IslandPressStyle())
    .disabled(replyState.isBusy)
    .accessibilityLabel("Insert emoji")
  }

  /// A line under the bar: the error, or "Connecting…" while a linked page finishes loading.
  private var caption: (text: String, color: Color)? {
    switch replyState {
    case .failed(let message): return (message, .red)
    case .connecting: return (L10n.tr("Connecting…"), IslandInk.secondary)
    default: return nil
    }
  }

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !replyState.isBusy
  }

  private func send() {
    guard canSend else { return }
    onSend(text)
  }

  /// The palette inserts into the first responder, so the field takes focus first.
  private func openEmojiPalette() {
    focused = true
    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
  }
}
