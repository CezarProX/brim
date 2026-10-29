// ReplyConnectionsSettingsSection.swift
// Brim
//
// The secondary place to manage WhatsApp and Telegram replies: status, the same inline QR panel
// the island uses, and Disconnect. Linking normally happens right from a notification.

import SwiftUI

struct ReplyConnectionsSettingsSection: View {
  var body: some View {
    SettingsSection(
      "Reply from the island",
      // swiftlint:disable:next line_length
      footer: "Messages replies work right away. For WhatsApp and Telegram, just reply to a notification in the island and scan the code it shows, or link here. Brim keeps a private, hidden web session that talks only to that service. Reply text is never stored or logged."
    ) {
      ReplyConnectionRow(session: WebMessengers.whatsApp, name: "WhatsApp")
      ReplyConnectionRow(session: WebMessengers.telegram, name: "Telegram")
    }
  }
}

private struct ReplyConnectionRow: View {
  @ObservedObject var session: WebMessengerSession
  let name: String
  @State private var linker: ReplyLinker?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        NotificationAppIcon(content: NotificationContent(bundleID: bundleID, appName: name), size: 22)
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: name).font(.body.weight(.medium))
          Text(verbatim: status).font(.caption).foregroundStyle(session.isLinked ? .green : .secondary)
        }
        Spacer()
        if session.isLinked || session.state != .off {
          Button("Disconnect") { disconnect() }
        }
        if !session.isLinked || session.state == .needsLogin {
          Button(linker == nil ? "Link…" : "Hide Code") { linker == nil ? showCode() : hideCode() }
        }
      }
      if let linker {
        ReplyLinkPanelHost(linker: linker, onClose: hideCode)
          .padding(14)
          .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          .environment(\.colorScheme, .dark)
          .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
      }
    }
    .animation(.spring(duration: 0.35, bounce: 0.1), value: linker == nil)
    .onAppear { if session.isLinked { session.activate() } }
    .onDisappear { hideCode() }
  }

  private var status: String {
    if session.isLinked { return WebMessengerText.status(.connected, channel: session.channel) }
    return session.state == .off ? L10n.tr("Not linked") : WebMessengerText.status(session.state, channel: session.channel)
  }

  private func showCode() {
    let panel = ReplyLinker(session: session)
    panel.onLinked = { hideCode() }
    linker = panel
    panel.start()
  }

  private func hideCode() {
    linker?.stop()
    linker = nil
  }

  private func disconnect() {
    hideCode()
    Task { await session.disconnect() }
  }

  private var bundleID: String {
    session.channel == .telegram ? "ru.keepcoder.Telegram" : "net.whatsapp.WhatsApp"
  }
}
