import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Brim

/// The Remove Background widget: images run the moment they arrive, one card each, and the
/// footer says where the cutouts went. Renders land in `.renders/remove-background-*.png`.
@MainActor
@Suite(.serialized)
struct RemoveBackgroundTests {
  private func image(_ name: String, in folder: URL, color: NSColor = .systemTeal) throws -> URL {
    let url = folder.appendingPathComponent(name)
    let size = 64
    let context = try #require(CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QS-RB-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A processor that copies the source to "-cutout.png", or fails for names with "fail".
  private static let fake: RemoveBackgroundSession.Processor = { source, _ in
    if source.lastPathComponent.contains("fail") { throw FileTrayError.failed("No subject found.") }
    let output = source.deletingPathExtension().appendingPathExtension("cutout.png")
    try? FileManager.default.removeItem(at: output)
    try FileManager.default.copyItem(at: source, to: output)
    return output
  }

  @Test func addedImagesRunRightAwayWithoutAnotherClick() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = RemoveBackgroundSession(process: Self.fake, policy: { TransformOutputPolicy() })
    let queued = session.add([try image("a.png", in: dir), try image("b.png", in: dir)])
    #expect(queued == 2)
    #expect(session.isWorking)
    await session.finish()
    #expect(!session.isWorking)
    #expect(session.results.map(\.lastPathComponent) == ["a.cutout.png", "b.cutout.png"])
    #expect(session.items.allSatisfy { $0.preview != nil })
    #expect(session.status == "2 saved next to the originals")
  }

  @Test func skipsNonImagesAndRepeats() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = RemoveBackgroundSession(process: Self.fake, policy: { TransformOutputPolicy() })
    let picture = try image("a.png", in: dir)
    let text = dir.appendingPathComponent("notes.txt")
    try "hi".write(to: text, atomically: true, encoding: .utf8)
    #expect(session.add([picture, text, picture]) == 1)
    await session.finish()
    #expect(session.add([picture]) == 0)
    #expect(session.items.count == 1)
    #expect(session.status == "Saved next to the original")
  }

  @Test func failuresShowAShortReasonAndTheCount() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = RemoveBackgroundSession(process: Self.fake, policy: { TransformOutputPolicy(destination: .downloads) })
    session.add([try image("ok.png", in: dir), try image("fail.png", in: dir)])
    await session.finish()
    #expect(session.items.last?.state == .failed("No subject found"))
    #expect(session.status == "1 saved · 1 failed")
  }

  @Test func doneClearsBackToTheDropZone() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = RemoveBackgroundSession(process: Self.fake, policy: { TransformOutputPolicy() })
    session.add([try image("a.png", in: dir)])
    session.clear()
    #expect(session.items.isEmpty)
    #expect(!session.isWorking)
    // A new run after clearing still starts by itself.
    session.add([try image("b.png", in: dir)])
    await session.finish()
    #expect(session.results.count == 1)
  }

  @Test func copyPutsPNGAndFileOnThePasteboard() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try image("a.png", in: dir)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("qs-rb-\(UUID().uuidString)"))
    RemoveBackgroundSession(process: Self.fake).copy(url, to: pasteboard)
    #expect(pasteboard.data(forType: .png) != nil)
    #expect(pasteboard.string(forType: .fileURL) == url.absoluteString)
  }

  /// The real on-device path: saves a transparent PNG, or says plainly that it found no subject.
  @Test func realCutoutEitherSavesAPNGOrSaysWhy() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let session = RemoveBackgroundSession(policy: { TransformOutputPolicy() })
    session.add([try image("subject.png", in: dir, color: .systemRed)])
    await session.finish()
    let state = try #require(session.items.first?.state)
    switch state {
    case .done(let url):
      #expect(url.pathExtension == "png")
      #expect(FileManager.default.fileExists(atPath: url.path))
    case .failed(let message):
      #expect(message.count <= 60)
    default:
      Issue.record("Still running after finish: \(state)")
    }
  }

  // MARK: Renders

  @Test func renders() async throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let empty = RemoveBackgroundSession(process: Self.fake)
    try await write(empty, name: "empty")

    let done = RemoveBackgroundSession(process: Self.fake, policy: { TransformOutputPolicy() })
    done.add([
      try image("IMG_5427.png", in: dir), try image("portrait.png", in: dir, color: .systemPink),
      try image("fail.png", in: dir),
    ])
    await done.finish()
    try await write(done, name: "results")

    let slow = RemoveBackgroundSession(process: { source, policy in
      try await Task.sleep(for: .seconds(30))
      return try await Self.fake(source, policy)
    })
    slow.add([try image("one.png", in: dir), try image("two.png", in: dir)])
    try await write(slow, name: "working")
    slow.clear()
  }

  private func write(_ session: RemoveBackgroundSession, name: String) async throws {
    let size = CGSize(width: 600, height: IslandWidgetTile.removeBackground.openHeight)
    let root = VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack(spacing: 10) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
          .background(IslandFill.raised, in: Circle())
        IslandWidgetIcon(tile: .removeBackground, size: 22)
        Text("Remove Background").font(IslandFont.title)
      }
      .foregroundStyle(IslandInk.primary).frame(height: 28)
      RemoveBackgroundWidgetView(session: session)
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
    try await Task.sleep(for: .milliseconds(1200))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let renders = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
    try png.write(to: renders.appendingPathComponent("remove-background-\(name).png"))
  }
}
