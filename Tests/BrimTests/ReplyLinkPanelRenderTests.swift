import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the inline link panel in every phase, and the island card with the panel open, to
/// .renders/ for visual review.
@MainActor
@Suite(.serialized)
struct ReplyLinkPanelRenderTests {
  private let item = NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Anna Kowalski",
                                         body: "Are we still on for dinner tonight?")

  private static let demoCode = LinkCode.payload("2@BrimRenderDemo,AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+/=,Zz==")

  private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(700))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    return bitmap
  }

  private func panel(_ phase: LinkPhase, channel: ReplyChannel = .whatsApp) -> some View {
    ReplyLinkPanel(channel: channel, phase: phase, hasDraft: true, onClose: {})
      .padding(14).frame(width: 372)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  @Test func rendersEveryPhase() async throws {
    let phases: [(LinkPhase, ReplyChannel)] = [
      (.loadingCode, .whatsApp), (.code(Self.demoCode), .whatsApp), (.linking, .whatsApp), (.success, .whatsApp),
      (.failed(.noCode), .whatsApp), (.code(Self.demoCode), .telegram), (.failed(.needsPassword), .telegram),
    ]
    let view = VStack(spacing: 14) { ForEach(Array(phases.enumerated()), id: \.offset) { panel($0.element.0, channel: $0.element.1) } }
      .padding(20).background(Color(white: 0.2))
    let bitmap = try await render(view, size: CGSize(width: 412, height: 1660), name: "reply-link-phases.png")
    #expect(bitmap.pixelsWide > 0)
    #expect(ReplyQRCache.image(for: Self.demoCode) != nil)
  }

  @Test func rendersTheCardWithThePanelOpen() async throws {
    let height = NotificationCardMetrics.bodyHeight(supportsReply: true, linking: true)
    let view = VStack(spacing: 16) {
      NotificationCardView(content: item, draft: .constant("On my way!"), linkPhase: .code(Self.demoCode))
        .frame(height: height, alignment: .top)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      NotificationCardView(content: item, draft: .constant("On my way!"), linkPhase: .success)
        .frame(height: height, alignment: .top)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      NotificationCardView(content: item, replyState: .connecting, draft: .constant("On my way!"))
        .frame(height: NotificationCardMetrics.withReply, alignment: .top)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    .padding(20).background(Color(white: 0.2))
    _ = try await render(view, size: CGSize(width: 412, height: 2 * height + NotificationCardMetrics.withReply + 72),
                         name: "reply-link-card.png")
  }

  @Test func rendersTheOnboardingPage() async throws {
    let bitmap = try await DropletRender.png(
      OnboardingView(page: .replies, replyPhase: .code(Self.demoCode)), size: OnboardingView.size,
      name: "onboarding-replies.png", background: .clear)
    #expect(bitmap.pixelsWide > 0)
  }
}
