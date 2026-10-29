import AVFoundation
import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Screenshot, DropClip and the Recording result inside the opened-widget chrome.
/// Renders land in `.renders/apps-<app>-<state>.png`.
@MainActor
@Suite(.serialized)
struct CaptureAppsRenderTests {
  private func render<V: View>(_ tile: IslandWidgetTile, _ name: String, _ content: V) async throws {
    let size = CGSize(width: 600, height: tile.openHeight)
    let root = VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack(spacing: 10) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
          .background(IslandFill.raised, in: Circle())
        IslandWidgetIcon(tile: tile, size: 22)
        Text(tile.title).font(IslandFont.title)
      }
      .foregroundStyle(IslandInk.primary).frame(height: 28)
      content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
    .frame(width: size.width, height: size.height, alignment: .top)
    .background(Color.black)
    .environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let renders = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
    try png.write(to: renders.appendingPathComponent("apps-\(name).png"))
  }

  private func tempShelf() -> ShelfStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QS-shelf-\(UUID().uuidString)")
    return ShelfStore(directory: dir)
  }

  private func picture(_ color: NSColor, size: CGSize = CGSize(width: 640, height: 400)) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
      color.setFill()
      rect.fill()
      NSColor.white.withAlphaComponent(0.8).setFill()
      NSBezierPath(roundedRect: rect.insetBy(dx: 60, dy: 60), xRadius: 20, yRadius: 20).fill()
      return true
    }
  }

  // MARK: Screenshot

  @Test func screenshotStates() async throws {
    let empty = tempShelf()
    try await render(.screenshot, "screenshot-empty", ScreenshotIslandView(shelf: empty, shelfEnabled: { true }))
    let off = tempShelf()
    try await render(.screenshot, "screenshot-shelf-off", ScreenshotIslandView(shelf: off, shelfEnabled: { false }))
    let full = tempShelf()
    for color in [NSColor.systemBlue, .systemOrange, .systemPurple, .systemGreen, .systemPink] {
      full.add(picture(color), id: UUID())
    }
    try await render(.screenshot, "screenshot-recent", ScreenshotIslandView(shelf: full, shelfEnabled: { true }))
    #expect(full.entries.count == 5)
  }

  // MARK: DropClip

  @Test func dropClipStates() async throws {
    try await render(.dropClip, "dropclip-off", DropClipIslandView(readState: { (false, false) }))
    try await render(.dropClip, "dropclip-needs-access", DropClipIslandView(readState: { (true, false) }))
    try await render(.dropClip, "dropclip-ready", DropClipIslandView(readState: { (true, true) }))
  }

  @Test func dropClipActionsWorkOnTheTryItText() async {
    let model = DropClipModel()
    model.begin(SelectionSnapshot(text: "hello brave world", bounds: nil, bundleID: nil, appName: nil))
    await model.perform(.count)
    #expect(model.outcome?.body == "3 words · 17 characters")
    await model.perform(.titleCase)
    #expect(model.outcome?.body == "Hello Brave World")
    #expect(!model.actions.isEmpty)
  }

  // MARK: Recording

  @Test func recordingResultStates() async throws {
    var result = RecordingResult(
      url: URL(fileURLWithPath: "/Users/me/Desktop/Screen Recording 2026-10-27 at 9.41.mov"), duration: 94, bytes: 48_300_000)
    result.thumbnail = picture(.systemTeal, size: CGSize(width: 480, height: 300))
    try await render(.recording, "recording-result", RecordingResultCard(
      result: result, studio: {}, share: { _ in }, close: {}))
    result.thumbnail = nil
    try await render(.recording, "recording-no-thumbnail", RecordingResultCard(result: result, studio: {}, share: { _ in }, close: {}))
  }

  /// A real one-second video, read back the way "Edit in Studio" reads a native recording.
  @Test func studioReadsMetadataFromAPlainVideo() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QS-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }
    try await Self.writeVideo(to: url, width: 320, height: 200, frames: 30)
    let metadata = try #require(await StudioWindowController.metadata(forVideoAt: url, scale: 2))
    #expect(metadata.pixelWidth == 320 && metadata.pixelHeight == 200)
    #expect(metadata.pointWidth == 160)
    #expect(metadata.source == .imported)
    #expect(abs(metadata.duration - 1) < 0.2)
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope.mov")
    #expect(await StudioWindowController.metadata(forVideoAt: missing) == nil)
  }

  private static func writeVideo(to url: URL, width: Int, height: Int, frames: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frames {
      var buffer: CVPixelBuffer?
      CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
      let pixels = try #require(buffer)
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
  }
}
