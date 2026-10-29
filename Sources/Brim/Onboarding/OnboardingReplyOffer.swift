// OnboardingReplyOffer.swift
// Brim
//
// The tour's one-time "Reply from the notch" page. It appears only when WhatsApp or Telegram is
// installed and not linked yet, and only once: after it has been shown (linked or skipped) it
// never comes back; replying to a notification links in place from then on.

import AppKit
import SwiftUI

enum ReplyLinkOffer {
  static let offeredKey = "replyLinkOffered"
  static let bundleIDs: [ReplyChannel: [String]] = [
    .whatsApp: ["net.whatsapp.WhatsApp", "net.whatsapp.WhatsAppSMB", "desktop.WhatsApp"],
    .telegram: ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.tdesktop.Telegram"],
  ]

  /// Channels worth offering, in display order. Empty once offered.
  static func channels(installed: (ReplyChannel) -> Bool, linked: (ReplyChannel) -> Bool, offered: Bool) -> [ReplyChannel] {
    guard !offered else { return [] }
    return [ReplyChannel.whatsApp, .telegram].filter { installed($0) && !linked($0) }
  }

  static func isInstalled(_ channel: ReplyChannel) -> Bool {
    (bundleIDs[channel] ?? []).contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
  }

  static func pending(defaults: UserDefaults = .standard) -> [ReplyChannel] {
    channels(installed: isInstalled, linked: ReplyAvailability.isConnected, offered: defaults.bool(forKey: offeredKey))
  }

  static func markOffered(defaults: UserDefaults = .standard) { defaults.set(true, forKey: offeredKey) }
}

/// State of the tour's reply page: which messenger's code is showing, and its linker.
@MainActor
final class TourReplyModel: ObservableObject {
  @Published private(set) var channel: ReplyChannel
  @Published private(set) var linker: ReplyLinker?
  /// Renders and tests pin a phase instead of loading the real site.
  let previewPhase: LinkPhase?
  private let defaults: UserDefaults

  init(previewPhase: LinkPhase? = nil, defaults: UserDefaults = .standard) {
    self.previewPhase = previewPhase
    self.defaults = defaults
    channel = ReplyLinkOffer.pending(defaults: defaults).first
      ?? (ReplyLinkOffer.isInstalled(.telegram) && !ReplyLinkOffer.isInstalled(.whatsApp) ? .telegram : .whatsApp)
  }

  func appear() {
    ReplyLinkOffer.markOffered(defaults: defaults)
    start()
  }

  func select(_ next: ReplyChannel) {
    guard next != channel else { return }
    stop()
    channel = next
    start()
  }

  func disappear() { stop() }

  private func start() {
    guard previewPhase == nil, linker == nil, let session = WebMessengers.session(for: channel) else { return }
    let panel = ReplyLinker(session: session)
    linker = panel
    panel.start()
  }

  private func stop() {
    linker?.stop()
    linker = nil
    WebMessengers.session(for: channel)?.suspend()
  }
}

/// The open island on the reply page: the same QR panel the notification card shows.
struct TourReplyIsland: View {
  @ObservedObject var model: TourReplyModel

  var body: some View {
    Group {
      if let phase = model.previewPhase {
        ReplyLinkPanel(channel: model.channel, phase: phase)
      } else if let linker = model.linker {
        ReplyLinkPanelHost(linker: linker)
      }
    }
    .padding(.horizontal, 14).padding(.top, 36)
    .onAppear { model.appear() }
    .onDisappear { model.disappear() }
  }
}

/// The two choice rows under the copy.
struct TourReplyOptions: View {
  @ObservedObject var model: TourReplyModel

  var body: some View {
    TourChoiceRow(symbol: "message.fill", title: "WhatsApp", selected: model.channel == .whatsApp) { model.select(.whatsApp) }
    TourChoiceRow(symbol: "paperplane.fill", title: "Telegram", selected: model.channel == .telegram) { model.select(.telegram) }
  }
}
