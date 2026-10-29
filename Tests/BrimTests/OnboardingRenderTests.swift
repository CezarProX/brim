import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders every page of the first-run tour to `.renders/onboarding-<page>.png`, to compare the
/// island on each page with the real island.
@MainActor
@Suite(.serialized)
struct OnboardingRenderTests {
  @Test func everyPage() async throws {
    for page in OnboardingPage.allCases { try await render(page) }
  }

  private func render(_ page: OnboardingPage) async throws {
    let size = OnboardingMetrics.size
    let flow = OnboardingFlow(page: page, pages: OnboardingPage.allCases)
    #expect(flow.page == page)
    let host = NSHostingView(rootView: OnboardingView(flow: flow))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1800))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("onboarding-\(page.rawValue)-\(page).png"))
  }
}
