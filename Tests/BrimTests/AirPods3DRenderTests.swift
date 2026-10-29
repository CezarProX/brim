import AppKit
import SceneKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the procedural AirPods models to `.renders/airpods-3d-*.png` so the look can be checked.
@MainActor
@Suite(.serialized)
struct AirPods3DRenderTests {
  private static let times: [TimeInterval] = [0.1, 0.3, 0.6, 1.1, 2.5, 4, 5.5, 7]

  private func rendersDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writePNG(_ image: NSImage, name: String) throws {
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: try rendersDirectory().appendingPathComponent("\(name).png"))
  }

  /// One large still per model plus an animation strip on black, like the island.
  @Test(arguments: AirPodsDeviceKind.allCases)
  func modelStills(kind: AirPodsDeviceKind) throws {
    guard AirPods3DSupport.isAvailable else { return }
    let hero = try #require(AirPods3DSnapshot.image(kind: kind, time: 0, pixelSize: CGSize(width: 504, height: 504),
                                                    reduceMotion: true))
    try writePNG(onBlack(hero), name: "airpods-3d-\(kind.rawValue)")
    let frames = try Self.times.map { time in
      try #require(AirPods3DSnapshot.image(kind: kind, time: time, pixelSize: CGSize(width: 168, height: 168)))
    }
    try writePNG(onBlack(strip(frames)), name: "airpods-3d-\(kind.rawValue)-motion")
  }

  /// The connect card as it ships: macOS's own banner clip when this Mac has it (else the 3D model).
  @Test func connectedCard() throws {
    let metrics = HUDMetrics(notchWidth: 190, closedHeight: 32)
    let devices: [(String, AccessoryModel, Int?, Int, Int?, Int?)] = [
      ("Alex’s AirPods Pro", .airPodsPro, 0x2024, 82, 76, 18), ("AirPods Max", .airPodsMax, 0x200A, 64, nil, nil),
      ("AirPods", .airPods4, 0x2019, 35, 41, 90), ("AirPods", .airPods3, 0x2013, 100, 100, 55),
    ]
    let cards = VStack(spacing: 12) {
      ForEach(devices, id: \.1.hashKey) { name, model, productID, left, right, caseLevel in
        card(AirPodsBatteries(name: name, symbol: AirPodsBatteries.symbol(for: model), left: left, right: right,
                              caseLevel: caseLevel, model: model, productID: productID), metrics: metrics)
      }
    }
    .padding(12).background(Color(white: 0.12))
    .environment(\.airPodsVisualStillTime, 0)
    .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: cards)
    renderer.scale = 2
    try writePNG(try #require(renderer.nsImage), name: "airpods-card-banner")
  }

  /// Exports the playing card frame by frame for review. Runs only when AIRPODS_PREVIEW_DIR is set.
  @Test func exportCardPreview() throws {
    guard let dir = ProcessInfo.processInfo.environment["AIRPODS_PREVIEW_DIR"] else { return }
    let metrics = HUDMetrics(notchWidth: 190, closedHeight: 32)
    for (slug, model, productID, levels) in [("pro", AccessoryModel.airPodsPro, 0x2024, (82, 76, 18)),
                                             ("max", .airPodsMax, 0x200A, (64, -1, -1))] {
      let folder = URL(fileURLWithPath: dir).appendingPathComponent(slug)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let pods = AirPodsBatteries(name: slug == "pro" ? "Alex’s AirPods Pro" : "AirPods Max",
                                  symbol: AirPodsBatteries.symbol(for: model), left: levels.0,
                                  right: levels.1 < 0 ? nil : levels.1, caseLevel: levels.2 < 0 ? nil : levels.2,
                                  model: model, productID: productID)
      for frame in 0..<360 {
        let view = card(pods, metrics: metrics).padding(10).background(Color.black)
          .environment(\.airPodsVisualStillTime, Double(frame) / 60).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent(String(format: "frame-%03d.png", frame)))
      }
    }
  }

  /// The real `SCNView` path: hosted in a window it renders the model on a clear background and
  /// animates while active.
  @Test func liveViewRendersAndAnimates() async throws {
    guard AirPods3DSupport.isAvailable else { return }
    let host = NSHostingView(rootView: AirPodsModelView(kind: .pro, symbol: "airpodspro", size: 120, active: true)
      .background(Color.black))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 120), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(1600))
    let view = try #require(sceneView(in: host))
    #expect(view.isPlaying)
    let yaw = view.scene?.rootNode.childNode(withName: "turntable", recursively: false)?.eulerAngles.y ?? 0
    #expect(abs(yaw - AirPods3DMotion.restPose.yaw) > 0.01, "the model should be turning")
    let shot = view.snapshot()
    try writePNG(onBlack(shot), name: "airpods-3d-live")
    let tiff = try #require(shot.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    let corner = bitmap.colorAt(x: 1, y: 1)
    #expect((corner?.alphaComponent ?? 1) < 0.05, "background should stay clear")
    #expect(center != nil)
  }

  private func sceneView(in view: NSView) -> SCNView? {
    if let scene = view as? SCNView { return scene }
    for child in view.subviews { if let found = sceneView(in: child) { return found } }
    return nil
  }

  private func card(_ pods: AirPodsBatteries, metrics: HUDMetrics) -> some View {
    let flash = IslandFlash(title: pods.name, symbol: pods.symbol, tint: .white, value: nil, until: .distantFuture,
                            kind: .bluetooth, detail: "Connected", airPods: pods, shortTitle: "Connected")
    let size = metrics.cardSize(for: flash)
    return HUDMorphView(flash: flash, metrics: metrics, expanded: true)
      .background(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).fill(.black)
        .frame(width: size.width, height: size.height))
  }

  private func strip(_ frames: [NSImage]) -> NSImage {
    let side = frames.first?.size.width ?? 168
    let image = NSImage(size: CGSize(width: side * CGFloat(frames.count), height: side))
    image.lockFocus()
    for (index, frame) in frames.enumerated() {
      frame.draw(in: CGRect(x: side * CGFloat(index), y: 0, width: side, height: side))
    }
    image.unlockFocus()
    return image
  }

  private func onBlack(_ image: NSImage) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    NSColor.black.setFill()
    CGRect(origin: .zero, size: image.size).fill()
    image.draw(in: CGRect(origin: .zero, size: image.size))
    result.unlockFocus()
    return result
  }
}

private extension AccessoryModel {
  var hashKey: String { "\(self)" }
}
