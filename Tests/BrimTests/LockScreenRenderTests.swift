import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct LockScreenRenderTests {
  private func sampleArtwork() -> NSImage {
    NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
      NSGradient(colors: [NSColor(red: 0.98, green: 0.35, blue: 0.45, alpha: 1),
                          NSColor(red: 0.35, green: 0.2, blue: 0.85, alpha: 1)])?.draw(in: rect, angle: 55)
      return true
    }
  }

  private func scene(look: LockScreenLook) -> some View {
    let snapshot = NowPlayingSnapshot(
      source: .music, title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
      duration: 243, position: 96, isPlaying: true)
    let content = LockCardsContent(
      media: LockMediaInfo(track: NowPlayingTrack(snapshot: snapshot, artwork: sampleArtwork())),
      timer: LockTimerInfo(title: "Focus", symbol: "brain.head.profile", tint: .orange, duration: 1500,
                           endDate: Date().addingTimeInterval(17 * 60 + 42), pausedRemaining: nil),
      awake: LockAwakeInfo(until: Date().addingTimeInterval(3600)))
    let items = [
      LockStatusItem(id: "b", symbol: "battery.75percent", title: "78%", detail: "Battery", tint: .white),
      LockStatusItem(id: "c", symbol: "calendar", title: "Design review", detail: "10:30 AM",
                     tint: Color(red: 1, green: 0.27, blue: 0.23)),
    ]
    let screen = CGRect(x: 0, y: 0, width: 900, height: 1200)
    let layout = LockScreenLayout.plan(
      LockCardInputs(hasMedia: true, timerActive: true, awakeActive: true, statusItemCount: 2), screen: screen)
    return ZStack(alignment: .topLeading) {
      LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.55), Color(red: 0.85, green: 0.4, blue: 0.5),
                              Color(red: 0.98, green: 0.7, blue: 0.4)], startPoint: .top, endPoint: .bottom)
      Text("9:41").font(.system(size: 120, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity).padding(.top, 70)
      if let row = layout.statusRow {
        LockStatusRowView(items: items, look: look)
          .offset(x: row.minX, y: screen.height - row.maxY)
      }
      if let frame = layout.cardsFrame {
        LockCardsStack(content: content, kinds: layout.cards.map(\.kind), look: look, actions: LockCardActions())
          .offset(x: frame.minX, y: screen.height - frame.maxY)
      }
    }
    .frame(width: screen.width, height: screen.height)
  }

  @Test(arguments: [LockScreenLook.liquid, .dark])
  func rendersCardsOverWallpaper(look: LockScreenLook) async throws {
    let size = CGSize(width: 900, height: 1200)
    let host = NSHostingView(rootView: scene(look: look).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("lockscreen-\(look.rawValue).png"))
    #expect(png.count > 10_000)
  }
}
