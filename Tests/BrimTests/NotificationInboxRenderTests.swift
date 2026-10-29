import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct NotificationInboxRenderTests {
  private let now = Date()

  private var samKey: InboxConversation.ID {
    InboxConversation.key(for: NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Sam Rivera"))
  }

  private var inbox: NotificationInbox {
    NotificationInbox()
      .recording(NotificationContent(bundleID: "ru.keepcoder.Telegram", appName: "Telegram", title: "Lena Park",
                                     body: "Standup moved to 3 pm", date: now.addingTimeInterval(-240)))
      .recording(NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Sam Rivera",
                                     body: "Look", date: now.addingTimeInterval(-30)))
      .recording(NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Sam Rivera",
                                     body: "Look at the notch 👀", date: now.addingTimeInterval(-10)))
      .recordingReply("Haha which one?", to: samKey, at: now.addingTimeInterval(-8))
      .recording(NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Sam Rivera",
                                     body: "The new island on my Mac. It shows my messages and I can answer from there",
                                     date: now.addingTimeInterval(-5)))
      .recording(NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Mia Chen",
                                     body: "Dinner at 8? I found a tiny Italian place 🍝", date: now))
  }

  @Test func layoutGrowsWithRowsAndReplyBar() {
    let base = NotificationInboxLayout.height(count: 2, threadOpen: false, linking: false)
    #expect(NotificationInboxLayout.height(count: 3, threadOpen: false, linking: false) > base)
    #expect(NotificationInboxLayout.height(count: 2, threadOpen: true, linking: false) > base)
    #expect(NotificationInboxLayout.height(count: 9, threadOpen: false, linking: false)
      == NotificationInboxLayout.height(count: NotificationInboxLayout.visibleRows, threadOpen: false, linking: false))
    #expect(NotificationInboxLayout.height(count: 0, threadOpen: false, linking: false) == NotificationInboxLayout.emptyHeight)
  }

  @Test func rendersListOpenRowAndEmptyState() async throws {
    let conversations = inbox.conversations
    let width = IslandPageLayout.trayWidth
    let view = VStack(spacing: 20) {
      NotificationInboxPage(conversations: conversations, now: now)
        .frame(width: width, height: NotificationInboxLayout.height(count: conversations.count, threadOpen: false, linking: false))
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      NotificationInboxPage(conversations: conversations, openID: samKey, now: now)
        .frame(width: width, height: NotificationInboxLayout.height(count: conversations.count, threadOpen: true, linking: false))
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      NotificationInboxPage(conversations: [], now: now)
        .frame(width: width, height: NotificationInboxLayout.emptyHeight)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    .padding(24).background(Color(white: 0.2))
    let size = CGSize(width: width + 48, height: 900)
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
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("notification-inbox.png"))
  }
}
