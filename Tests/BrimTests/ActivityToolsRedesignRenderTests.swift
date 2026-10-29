import AppKit
import SwiftUI
import Testing
import Vision

@testable import Brim

@MainActor
@Suite(.serialized)
struct ActivityToolsRedesignRenderTests {
  @Test func launcherShowsEveryToolInAThreeColumnGrid() async throws {
    let center = ActivityCenter()
    #expect(ActivityToolsView.primaryActivities.count == 12)
    #expect(Set(ActivityToolsView.primaryActivities).count == 12)
    let bitmap = try await render(
      ActivityToolsView(center: center, selection: .constant(nil)), name: "activity-tools-grid",
      size: CGSize(width: 424, height: 232))
    let text = try recognize(bitmap).lowercased()

    for title in ["timer", "calendar", "batteries", "dictation", "memos", "awake", "notes", "stats"] {
      #expect(text.contains(title), "The \(title) tile must be visible without scrolling. OCR: \(text)")
    }
  }

  @Test func idleFocusRequiresAnExplicitStartAfterChoosingAPreset() async throws {
    let model = FocusTimerModel()
    defer { model.stop() }
    let bitmap = try await render(
      FocusActivityView(model: model), name: "focus-idle-explicit-start",
      size: CGSize(width: 400, height: 156))
    let text = try recognize(bitmap).lowercased()

    #expect(!model.isActive)
    // The dial defaults to 25 minutes and nothing starts until Start is pressed.
    #expect(text.contains("25:00"))
    #expect(text.contains("start timer"))
  }

  @Test func emptySummaryUsesCompactNavigationActions() async throws {
    let center = ActivityCenter()
    let bitmap = try await render(
      ActivitySummaryView(center: center, onSelect: { _ in }), name: "activity-summary-empty",
      size: CGSize(width: 364, height: 44))
    let text = try recognize(bitmap).lowercased()

    #expect(text.contains("calendar") || center.calendar.meeting != nil)
    #expect(text.contains("batteries") || !center.batteries.devices.isEmpty)
  }

  /// The running timer fills the island's activity area and sits in its middle, the way every
  /// container shows it (inside a ScrollView), instead of hugging the top-left corner.
  @Test func runningTimerIsCenteredInTheIslandArea() async throws {
    let model = FocusTimerModel()
    defer { model.stop() }
    model.start(minutes: 25)
    let size = CGSize(width: 500, height: 228)
    let bitmap = try await render(
      ScrollView { FocusActivityView(model: model).frame(maxWidth: .infinity, alignment: .topLeading) },
      name: "focus-running-centered", size: size)
    let ink = try #require(Self.inkBounds(bitmap))
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    let center = CGPoint(x: ink.midX / scale, y: ink.midY / scale)
    #expect(abs(center.x - size.width / 2) <= 14, "content center x \(center.x) in \(size.width)")
    #expect(abs(center.y - size.height / 2) <= 14, "content center y \(center.y) in \(size.height)")
    #expect(ink.height / scale >= 140, "the ring should use the height, not stay small: \(ink.height / scale)")
  }

  /// The box around every pixel brighter than the black background, in pixels.
  private static func inkBounds(_ bitmap: NSBitmapImageRep) -> CGRect? {
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              color.redComponent + color.greenComponent + color.blueComponent > 0.25 else { continue }
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
  }

  private func render<V: View>(_ view: V, name: String, size: CGSize) async throws
    -> NSBitmapImageRep
  {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(.white).background(.black).preferredColorScheme(.dark))
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let directory = URL(fileURLWithPath: "/tmp/brim-expansion-renders", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(
      to: directory.appendingPathComponent(name + ".png"))
    return bitmap
  }

  private func recognize(_ bitmap: NSBitmapImageRep) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(
      separator: " ")
  }
}
