import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
private final class AppsStubSpeech: DictationSpeechProviding {
  var supportsOnDeviceRecognition = true
  var authorizationError: Error?
  private var update: ((String, Bool) -> Void)?
  func requestAuthorization() async throws { if let authorizationError { throw authorizationError } }
  func begin(update: @escaping (String, Bool) -> Void, failure: @escaping (Error) -> Void) throws { self.update = update }
  func stop() {}
  func emit(_ text: String) { update?(text, false) }
}

@MainActor
private final class AppsStubInsertion: DictationInsertionProviding {
  func captureFocusedTarget() -> Bool { true }
  func insert(_ text: String) throws {}
  func discardTarget() {}
}

@MainActor
private final class AppsStubClipboard: DictationClipboardWriting { func copy(_ text: String) {} }

private struct Denied: LocalizedError { var errorDescription: String? { "The microphone is off for Brim. Turn it on, then try again." } }

/// Notes, Obsidian, Text Capture, Dictation and Voice Memo as the island opens them, in their
/// first-run and working states. PNGs land in `.renders/apps-<app>-<state>.png`.
@MainActor
@Suite(.serialized)
struct ProductivityAppsRenderTests {
  private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apps-render-\(UUID())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// The opened-widget frame (back chevron, icon, title, subtitle) around a tool's content.
  private func opened<V: View>(_ tile: IslandWidgetTile, @ViewBuilder _ content: () -> V) -> some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack(spacing: 10) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
          .background(IslandFill.raised, in: Circle())
        IslandWidgetIcon(tile: tile, size: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(tile.title).font(IslandFont.title)
          if let subtitle = tile.subtitle { Text(subtitle).font(IslandFont.body).foregroundStyle(IslandInk.secondary) }
        }
        Spacer(minLength: 0)
      }
      .frame(height: 34)
      content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
    .frame(width: 800, height: tile.openHeight, alignment: .top)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
  }

  private func render<V: View>(_ tile: IslandWidgetTile, _ name: String, @ViewBuilder _ content: () -> V) async throws {
    let view = opened(tile, content).foregroundStyle(.white)
    _ = try await DropletRender.png(view, size: CGSize(width: 800, height: tile.openHeight), name: "apps-\(name).png", background: .black)
  }

  private func vault() throws -> URL {
    let root = tempDir().appendingPathComponent("Brain")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Projects"), withIntermediateDirectories: true)
    try "# Roadmap\n- [ ] Ship the island\n- [x] Write tests\n".write(to: root.appendingPathComponent("Projects/Roadmap.md"), atomically: true, encoding: .utf8)
    try "Buy milk".write(to: root.appendingPathComponent("Inbox.md"), atomically: true, encoding: .utf8)
    try "Welcome".write(to: root.appendingPathComponent("Start.md"), atomically: true, encoding: .utf8)
    return root
  }

  @Test func notes() async throws {
    let empty = NotesModel(directory: tempDir())
    try await render(.notes, "notes-empty") { NotesPanelView(notes: empty, obsidian: ObsidianModel(vaultPath: nil, obsidianConfig: nil), mode: .notes) }
    let model = NotesModel(directory: tempDir())
    let a = model.create(); model.update(a.id, text: "Groceries\nmilk, eggs"); model.togglePin(a.id)
    let b = model.create(); model.update(b.id, text: "# Launch checklist\nShip **Friday** with care.\n\n- [x] Draft copy\n- [ ] Record the demo\n- plain bullet")
    model.selectedID = b.id
    try await render(.notes, "notes-working") { NotesPanelView(notes: model, obsidian: ObsidianModel(vaultPath: nil, obsidianConfig: nil), mode: .notes) }
  }

  @Test func obsidian() async throws {
    let none = ObsidianModel(vaultPath: nil, obsidianConfig: nil)
    try await render(.obsidian, "obsidian-empty") { NotesPanelView(notes: NotesModel(directory: tempDir()), obsidian: none, mode: .obsidian) }
    let root = try vault()
    let model = ObsidianModel(vaultPath: root.path, obsidianConfig: nil)
    try await render(.obsidian, "obsidian-nonote") { NotesPanelView(notes: NotesModel(directory: tempDir()), obsidian: model, mode: .obsidian) }
    model.select("Projects/Roadmap.md")
    try await render(.obsidian, "obsidian-working") { NotesPanelView(notes: NotesModel(directory: tempDir()), obsidian: model, mode: .obsidian) }
  }

  @Test func textCapture() async throws {
    let settings = DropletRender.isolatedSettings()
    let history = TextCaptureHistory(file: tempDir().appendingPathComponent("h.json"))
    let model = TextCaptureModel(settings: settings, history: history)
    try await render(.textCapture, "textcapture-empty") { TextCaptureIslandView(model: model, history: history) }
    model.show(TextCaptureEntry(kind: .text, source: .area, text: "Invoice 2041\nTotal due: 128.40 EUR\nPay by 14 November"))
    try await render(.textCapture, "textcapture-working") { TextCaptureIslandView(model: model, history: history) }
  }

  @Test func dictation() async throws {
    let speech = AppsStubSpeech()
    let model = DictationModel(speech: speech, insertion: AppsStubInsertion(), clipboard: AppsStubClipboard())
    try await render(.dictation, "dictation-empty") { DictationActivityView(model: model) }
    await model.start()
    speech.emit("Let's move the review to Thursday afternoon and send the notes before lunch")
    try await Task.sleep(for: .milliseconds(100))
    try await render(.dictation, "dictation-working") { DictationActivityView(model: model) }
    model.stop()
    let denied = AppsStubSpeech()
    denied.authorizationError = Denied()
    let refused = DictationModel(speech: denied, insertion: AppsStubInsertion(), clipboard: AppsStubClipboard())
    await refused.start()
    refused.permissionIssue = .microphone
    try await render(.dictation, "dictation-error") { DictationActivityView(model: refused) }
  }

  @Test func voiceMemo() async throws {
    let empty = VoiceRecorderModel(directory: tempDir())
    try await render(.voiceMemo, "voicememo-empty") { VoiceMemosView(model: empty) }
    let dir = tempDir()
    for (offset, text) in [(0, "Call the dentist and move the appointment to next week."), (3600, nil), (90000, "Idea: a shelf for screenshots.")] {
      let date = Date().addingTimeInterval(-Double(offset))
      let url = dir.appendingPathComponent(VoiceRecorderModel.fileName(for: date))
      try Data().write(to: url)
      try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
      if let text { try text.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8) }
    }
    let model = VoiceRecorderModel(directory: dir)
    try await render(.voiceMemo, "voicememo-working") { VoiceMemosView(model: model) }
    try await render(.voiceMemo, "voicememo-expanded") { VoiceMemosView(model: model, expanded: model.memos.first?.url) }
  }
}
