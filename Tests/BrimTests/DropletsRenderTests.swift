import AppKit
import SwiftUI
import Testing
@testable import Brim

@MainActor
struct DropletsRenderTests {
  private func render<V: View>(_ view: V, size: CGSize, name: String, settle: Int = 250) async throws {
    let host = NSHostingView(rootView: view.padding(0).frame(width: size.width, height: size.height)
      .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(settle))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("\(name).png"))
    #expect(png.count > 4_000)
  }

  private let islandSize = CGSize(width: 560, height: 200)

  @Test("Termi-Notch renders colored shell output")
  func termi() async throws {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-r-\(UUID())")!)
    let model = TermiNotchModel(settings: settings)
    let session = TerminalSession(directory: "/Users/demo/projects/brim", columns: 80, rows: 8)
    session.showPreview("\u{1B}[1;36m~/projects/brim\u{1B}[0m \u{1B}[32mmain\u{1B}[0m \u{1B}[2m❯\u{1B}[0m ls -la\r\n"
      + "total 48\r\ndrwxr-xr-x  \u{1B}[34mSources\u{1B}[0m\r\n-rw-r--r--  Package.swift\r\n\u{1B}[1;31mfatal:\u{1B}[0m not a git repo\r\n"
      + "\u{1B}[1;36m~/projects/brim\u{1B}[0m \u{1B}[32mmain\u{1B}[0m \u{1B}[2m❯\u{1B}[0m ")
    let second = TerminalSession(directory: "/Users/demo", columns: 80, rows: 8)
    second.showPreview("$ ")
    model.adopt(session)
    model.adopt(second)
    model.selectedID = session.id
    try await render(TermiNotchIslandView(model: model), size: islandSize, name: "droplet-termi-notch")
  }

  @Test("Teleprompter renders the editor and the live preview")
  func teleprompter() async throws {
    let model = TeleprompterModel(settings: AppSettings(defaults: UserDefaults(suiteName: "qs-r-\(UUID())")!))
    model.script = "Welcome back to the channel.\n\nToday we are looking at how a small tool can quietly remove a dozen little frictions from your day.\n\nLet's get started."
    try await render(TeleprompterIslandView(), size: islandSize, name: "droplet-teleprompter-editor")
    TeleprompterModel.shared.script = model.script
    try await render(TeleprompterIslandView(), size: islandSize, name: "droplet-teleprompter-editor-filled")
    try await render(
      PrompterPreview(model: model), size: CGSize(width: 380, height: 150), name: "droplet-teleprompter-panel")
  }

  @Test("Text Capture renders a result and the history")
  func textCapture() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("qs-r-\(UUID())/h.json")
    let history = TextCaptureHistory(file: file)
    history.add(.init(kind: .text, source: .area, text: "Invoice #4021\nTotal due: $1,234.00"))
    history.add(.init(kind: .code, source: .area, text: "https://example.com/menu", symbology: "QR code"))
    let model = TextCaptureModel(settings: AppSettings(defaults: UserDefaults(suiteName: "qs-r-\(UUID())")!), history: history)
    await model.process([qrAndText()], source: .area)
    #expect(model.result?.text.lowercased().contains("scan") == true)
    #expect(model.result?.codes.first?.payload == "https://example.com/menu")
    try await render(TextCaptureIslandView(model: model, history: history), size: islandSize, name: "droplet-text-capture")
  }

  @Test("DropClip renders the island pad and the floating bar with a result")
  func dropClip() async throws {
    try await render(DropClipIslandView(), size: islandSize, name: "droplet-dropclip-island")
    let model = DropClipModel(settings: AppSettings(defaults: UserDefaults(suiteName: "qs-r-\(UUID())")!))
    model.begin(SelectionSnapshot(text: "the quick brown fox jumps over the lazy dog", bounds: nil, bundleID: nil, appName: nil))
    await model.perform(.count)
    try await render(DropClipBarView(model: model).padding(20), size: CGSize(width: 480, height: 150), name: "droplet-dropclip-bar")
  }

  private func qrAndText() -> CGImage {
    let context = CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSAttributedString(string: "Scan for the menu", attributes: [.font: NSFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: NSColor.black])
      .draw(at: CGPoint(x: 20, y: 220))
    NSGraphicsContext.restoreGraphicsState()
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data("https://example.com/menu".utf8), forKey: "inputMessage")
    let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 7, y: 7))
    if let cg = CIContext().createCGImage(qr, from: qr.extent) { context.draw(cg, in: CGRect(x: 20, y: 10, width: 200, height: 200)) }
    return context.makeImage()!
  }
}

private struct PrompterPreview: View {
  let model: TeleprompterModel
  var body: some View {
    VStack(spacing: 4) {
      TeleprompterScrollView(model: model)
      TeleprompterControls(model: model).padding(.horizontal, 10).padding(.bottom, 8)
    }
    .background(Color.black)
  }
}
