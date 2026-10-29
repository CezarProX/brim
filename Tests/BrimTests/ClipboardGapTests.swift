import AppKit
import Foundation
import SQLite3
import Testing

@testable import Brim

struct ClipboardSelectionTests {
  @Test func selectionKeepsClickOrder() {
    var selection = ClipboardSelection()
    selection.toggle("b"); selection.toggle("a"); selection.toggle("c")
    #expect(selection.ordered == ["b", "a", "c"])
    selection.toggle("a")
    #expect(selection.ordered == ["b", "c"])
    #expect(selection.targets(in: ["a", "b", "c"]) == ["b", "c"])
  }

  @Test func cursorMovesAndClamps() {
    var selection = ClipboardSelection()
    let ids = ["a", "b", "c"]
    selection.move(1, in: ids)
    #expect(selection.cursor == "a")
    selection.move(1, in: ids); selection.move(1, in: ids); selection.move(1, in: ids)
    #expect(selection.cursor == "c")
    selection.move(-5, in: ids)
    #expect(selection.cursor == "a")
    selection.move(1, in: [])
    #expect(selection.cursor == nil)
  }

  @Test func commandsFallBackToTheCursorAndPruneRemovedItems() {
    var selection = ClipboardSelection()
    selection.cursor = "b"
    #expect(selection.targets(in: ["a", "b"]) == ["b"])
    #expect(selection.targets(in: ["a"]).isEmpty)
    selection.selectAll(["a", "b", "c"])
    selection.prune(keeping: ["a", "c"])
    #expect(selection.ordered == ["a", "c"] && selection.cursor == nil)
  }

  @Test func pastePlansByKind() {
    #expect(ClipboardPastePlan.plan(for: [.text, .link, .color]) == .joinedText)
    #expect(ClipboardPastePlan.plan(for: [.file, .file]) == .allFiles)
    #expect(ClipboardPastePlan.plan(for: [.text, .image]) == .sequential)
    #expect(ClipboardPastePlan.joinedText(["one\n", "two"]) == "one\ntwo")
  }
}

struct ClipboardShortcutTests {
  private func command(_ key: ClipboardKey, cmd: Bool = false, shift: Bool = false, searching: Bool = false) -> ClipboardShortcut? {
    ClipboardShortcuts.command(for: key, command: cmd, shift: shift, option: false, searching: searching)
  }

  @Test func commandLettersMapToTheDocumentedShortcuts() {
    #expect(command(.character("c"), cmd: true) == .copy)
    #expect(command(.character("d"), cmd: true) == .deleteItem)
    #expect(command(.character("f"), cmd: true) == .focusSearch)
    #expect(command(.character("p"), cmd: true) == .togglePin)
    #expect(command(.character("b"), cmd: true) == .toggleBlur)
    #expect(command(.character("S"), cmd: true, shift: true) == .saveAs)
    #expect(command(.character("s"), cmd: true) == nil)
    #expect(command(.character("t"), cmd: true) == .tag)
    #expect(command(.character("a"), cmd: true) == .selectAll)
  }

  @Test func arrowsReturnAndEscape() {
    #expect(command(.left) == .move(-1) && command(.right) == .move(1))
    #expect(command(.returnKey) == .activate && command(.returnKey, cmd: true) == .pasteAll)
    #expect(command(.escape) == .cancel)
    #expect(command(.character(" ")) == .toggleSelect)
    #expect(command(.character("x")) == nil)
  }

  @Test func searchFieldKeepsTypingKeys() {
    #expect(command(.character("c"), cmd: true, searching: true) == nil)
    #expect(command(.character(" "), searching: true) == nil)
    #expect(command(.escape, searching: true) == .cancel)
    #expect(command(.down, searching: true) == .move(0))
  }
}

@MainActor
struct ClipboardCopyTogetherTests {
  @Test func joinsTextEntriesOnePerLine() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QS-Multi-\(UUID().uuidString)")
    let board = NSPasteboard(name: .init("QS-Multi-\(UUID().uuidString)"))
    defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
    let store = ClipboardStore(directory: directory, pasteboard: board)
    store.start()
    defer { store.stop() }
    for value in ["first", "https://example.com/two"] {
      board.clearContents(); board.setString(value, forType: .string)
      await store.captureChange()
    }
    let chosen = store.entries.reversed().map { $0 }
    #expect(store.copyTogether(chosen) == 2)
    #expect(board.string(forType: .string) == "first\nhttps://example.com/two")
    #expect(store.copyTogether([]) == 0)
  }
}

struct ClipboardImporterTests {
  @Test func datesNormalizeAcrossEpochs() {
    #expect(ClipboardImporters.date(from: 1_700_000_000).timeIntervalSince1970 == 1_700_000_000)
    #expect(ClipboardImporters.date(from: 1_700_000_000_000).timeIntervalSince1970 == 1_700_000_000)
    #expect(ClipboardImporters.date(from: 700_000_000).timeIntervalSinceReferenceDate == 700_000_000)
  }

  @Test func snifferPrefersTheClipTableWithATextColumn() {
    let guess = ImportSchemaSniffer.choose([
      ImportTableShape(name: "settings", columns: ["key", "value"]),
      ImportTableShape(name: "ClipboardItem", columns: ["id", "plain_text", "created_at"]),
    ])
    #expect(guess == ImportSchemaGuess(table: "ClipboardItem", textColumn: "plain_text", dateColumn: "created_at"))
    #expect(ImportSchemaSniffer.choose([ImportTableShape(name: "t", columns: ["a", "b"])]) == nil)
  }

  private func makeDatabase(_ sql: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QS-imp-\(UUID().uuidString).sqlite")
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    for statement in sql { #expect(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK) }
    sqlite3_close(db)
    return url
  }

  @Test func readsAnUnknownSchemaBySniffing() throws {
    let url = try makeDatabase([
      "CREATE TABLE clip_history (id INTEGER, plain_text TEXT, created_at REAL)",
      "INSERT INTO clip_history VALUES (1, 'older', 1700000000)",
      "INSERT INTO clip_history VALUES (2, 'newer', 1700005000)",
      "INSERT INTO clip_history VALUES (3, '   ', 1700009000)",
    ])
    defer { try? FileManager.default.removeItem(at: url) }
    let items = try SniffingSQLiteImporter.readItems(at: url, limit: 10)
    #expect(items.map(\.text) == ["newer", "older"])
    #expect(items[0].date.timeIntervalSince1970 == 1_700_005_000)
  }

  @Test func protectedFilesAreReportedNotCrashed() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-imp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(repeating: 7, count: 4096).write(to: folder.appendingPathComponent("clipboard.sqlite"))
    #expect(SniffingSQLiteImporter.databases(in: [folder]).isEmpty)
    guard case .unavailable = SniffingSQLiteImporter.importHistory(name: "X", folders: [folder], limit: 5) else {
      Issue.record("expected unavailable"); return
    }
    guard case .unavailable = SniffingSQLiteImporter.importHistory(name: "X", folders: [folder.appendingPathComponent("none")], limit: 5)
    else { Issue.record("expected unavailable"); return }
  }

  @Test func clipyKeyedArchiveYieldsTheCopiedText() throws {
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: ["public.utf8-plain-text", "NSStringPboardType", "hello from clipy"], requiringSecureCoding: false)
    #expect(ClipyImporter.text(inKeyedArchive: data) == "hello from clipy")
    #expect(ClipyImporter.text(inKeyedArchive: Data("junk".utf8)) == nil)
  }

  @Test func clipySnippetXMLContentsAreRead() {
    let xml = """
      <folders><folder><title>F</title><snippets>
      <snippet><title>a</title><content>first body</content></snippet>
      <snippet><title>b</title><content><![CDATA[second <body>]]></content></snippet>
      <snippet><title>c</title><content>  </content></snippet>
      </snippets></folder></folders>
      """
    #expect(ClipyImporter.snippets(inXML: Data(xml.utf8)) == ["first body", "second <body>"])
  }

  @Test func clipyFolderImportEndToEnd() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-clipy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try NSKeyedArchiver.archivedData(withRootObject: ["public.url", "clip body text"], requiringSecureCoding: false)
      .write(to: folder.appendingPathComponent("abc.data"))
    guard case .items(let items) = ClipyImporter.importHistory(from: [folder]) else { Issue.record("no items"); return }
    #expect(items.map(\.text) == ["clip body text"])
    guard case .unavailable = ClipyImporter.importHistory(from: [folder.appendingPathComponent("none")]) else {
      Issue.record("expected unavailable"); return
    }
  }
}

@MainActor
struct ClipboardUnreadableHistoryTests {
  /// A history file the app can't decode must survive the next copy (it used to be overwritten).
  @Test func unreadableHistoryIsSetAsideNotOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QS-Corrupt-\(UUID().uuidString)")
    let board = NSPasteboard(name: .init("QS-Corrupt-\(UUID().uuidString)"))
    defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = Data("[{\"from\": \"a newer build\"".utf8)
    try original.write(to: directory.appendingPathComponent("entries.json"))
    let store = ClipboardStore(directory: directory, pasteboard: board)
    store.start()
    defer { store.stop() }
    board.clearContents(); board.setString("fresh copy", forType: .string)
    await store.captureChange()
    store.flushPendingSave()
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    let backup = try #require(names.first { $0.hasPrefix("entries-unreadable-") })
    #expect(try Data(contentsOf: directory.appendingPathComponent(backup)) == original)
  }
}
