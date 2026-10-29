import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct NotificationCardRenderTests {
  private let samples: [NotificationContent] = [
    NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Anna Kowalski",
                        body: "Are we still on for dinner tonight? I booked the place near the river for 8."),
    NotificationContent(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "#design",
                        subtitle: "Maya Chen", body: "Pushed the new onboarding frames, can you take a look before standup?"),
    NotificationContent(bundleID: "com.apple.mail", appName: "Mail", title: "Stripe", subtitle: "Payment received",
                        body: "You received a payment of $240.00 from Acme Inc."),
  ]

  @Test func rendersCompactAndExpandedCards() async throws {
    let view = VStack(spacing: 16) {
      ForEach(samples) { item in
        NotificationCompactView(content: item, overflow: item.appName == "Slack" ? 2 : 0)
          .frame(width: 300, height: 36).background(Color.black, in: Capsule())
        NotificationCardView(content: item, overflow: item.appName == "Slack" ? 2 : 0)
          .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      }
      NotificationCardView(content: samples[0], replyState: .failed("Allow Brim to control Messages"))
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      VStack(spacing: 22) {
        NotificationReplyBar(channel: .whatsApp, text: .constant("On my way"))
        NotificationReplyBar(channel: .telegram, text: .constant(""), replyState: .connecting)
        NotificationReplyBar(channel: .messages, text: .constant(""), replyState: .sent)
        NotificationReplyBar(channel: .whatsApp, text: .constant(""), replyState: .failed("Connect WhatsApp in Settings to reply"))
      }
      .padding(16).frame(width: 372).background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    .padding(24).background(Color(white: 0.2))
    let size = CGSize(width: 440, height: 1120)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("notification-cards.png"))
  }
}
