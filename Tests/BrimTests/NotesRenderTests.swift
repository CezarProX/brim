import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite("Notes surfaces")
struct NotesRenderTests {
  private static let sample = """
    # Launch checklist
    Ship **Friday** with *care*, <u>underlined</u>, ~~dropped~~ and ==highlighted== notes, see [docs](https://example.com).

    - [x] Draft copy
    - [ ] Record the `demo`
    - plain bullet
    1. First
    2. Second
    ## Next
    > a quote
    """

  private func store() -> (NotesModel, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-surface-\(UUID())")
    let notes = NotesModel(directory: dir)
    let other = notes.create()
    notes.update(other.id, text: "Groceries\nmilk, eggs")
    notes.togglePin(other.id)
    let main = notes.create()
    notes.update(main.id, text: Self.sample)
    notes.selectedID = main.id
    return (notes, dir)
  }

  private func hasInk(_ bitmap: NSBitmapImageRep) -> Bool {
    var bright = 0
    for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
      for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) where (bitmap.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.8 { bright += 1 }
    }
    return bright > 50
  }

  @Test func islandWidgetRenders() async throws {
    let (notes, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let view = NotesPanelView(notes: notes, obsidian: ObsidianModel(vaultPath: nil), mode: .notes)
      .padding(14).foregroundStyle(.white)
    let bitmap = try await DropletRender.png(view, size: CGSize(width: 640, height: 330), name: "notes-island-widget.png", background: .black)
    #expect(hasInk(bitmap))
  }

  @Test func homeWidgetRenders() async throws {
    let (notes, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let view = NotesWidget(model: notes).padding(12).foregroundStyle(.white)
    let bitmap = try await DropletRender.png(view, size: CGSize(width: 330, height: 220), name: "notes-home-widget.png", background: .black)
    #expect(hasInk(bitmap))
  }

  @Test func floatingWindowRenders() async throws {
    let (notes, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bitmap = try await DropletRender.png(
      NotesWindowView(notes: notes), size: CGSize(width: 780, height: 520), name: "notes-window.png", background: .black)
    #expect(hasInk(bitmap))
  }

  @Test func windowAndIslandShareOneStore() {
    let (notes, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let id = notes.selected!.id
    // Both surfaces bind to the same model; an edit made through one is the text the other reads.
    NotesBinding.markdown(for: id, in: notes).wrappedValue = "# Edited in the window"
    #expect(notes.selected?.text == "# Edited in the window")
    let reopened = NotesModel(directory: dir)
    #expect(reopened.notes.first { $0.id == id }?.text == "# Edited in the window")
  }

  @Test func notesShortcutsAreUnassignedByDefaultAndPersist() {
    for id in [ShortcutID.showNotes, .newNote] {
      #expect(!ShortcutCatalog.defaultBinding(id).isSet)
      #expect(ShortcutCatalog.group(id) == .tools)
      #expect(ShortcutCatalog.ids(in: .tools).contains(id))
    }
    let settings = DropletRender.isolatedSettings()
    let binding = DropletShortcut(keyCode: kVK_ANSI_J, modifiers: Int(cmdKey | optionKey))
    #expect(ShortcutStore.set(.showNotes, to: binding, settings: settings, live: false) == nil)
    #expect(settings.showNotesShortcut == binding)
    #expect(ShortcutStore.set(.newNote, to: binding, settings: settings, live: false) == .usedBy(.showNotes))
    #expect(ShortcutStore.reset(.showNotes, settings: settings, live: false) == nil)
    #expect(!settings.showNotesShortcut.isSet)
  }
}
