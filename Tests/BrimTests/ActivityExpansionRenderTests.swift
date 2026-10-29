import AppKit
import SwiftUI
import Testing
import Vision

@testable import Brim

@MainActor
@Suite(.serialized)
struct ActivityExpansionRenderTests {
  @Test func focusControlsAndSharingFitExpandedCard() async throws {
    let focus = FocusTimerModel()
    defer { focus.stop() }
    focus.start(minutes: 25)
    let bitmap = try await render(FocusActivityView(model: focus), name: "focus-expanded")
    let text = try recognize(bitmap).lowercased()
    #expect(text.contains("pause"))
    #expect(text.contains("restart"))
    #expect(text.contains("stop"))
    let sharing = try await render(
      SharingActivityView(model: SharingActivityModel()), name: "sharing-expanded")
    #expect(try recognize(sharing).lowercased().contains("choose files"))
  }

  @Test func disconnectedCalendarAndDictationExplainExplicitStart() async throws {
    let calendar = try await render(
      CalendarActivityView(model: CalendarActivityModel()), name: "calendar-empty")
    #expect(try recognize(calendar).lowercased().contains("connect calendar"))
    let dictation = try await render(
      DictationActivityView(model: DictationModel()), name: "dictation-idle")
    #expect(try recognize(dictation).lowercased().contains("start"))
  }

  private func render<V: View>(_ view: V, name: String) async throws -> NSBitmapImageRep {
    let size = CGSize(width: 544, height: 260)
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
