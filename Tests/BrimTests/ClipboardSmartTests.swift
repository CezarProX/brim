import AppKit
import SQLite3
import Testing
@testable import Brim

private func entry(_ kind: ClipboardEntry.Kind = .text, text: String? = "x", age: TimeInterval = 0, pinned: Bool = false,
                   bytes: Int = 10, now: Date = Date()) -> ClipboardEntry {
    ClipboardEntry(id: UUID(), date: now.addingTimeInterval(-age), kind: kind, text: text,
                   fingerprint: UUID().uuidString, byteCount: bytes, pixelSize: nil, isPinned: pinned)
}

struct ClipboardClassifierTests {
    @Test(arguments: [
        ("a@b.co", true), ("first.last+tag@sub.example.org", true), ("mailto:hi@example.com", true),
        ("a@b.com, c@d.org", true), ("not an email", false), ("a@b", false), ("@example.com", false),
        ("see me at a@b.com tomorrow please", false), ("https://example.com/a@b.com", false), ("", false),
    ])
    func emails(_ text: String, _ expected: Bool) {
        #expect(ClipboardClassifier.isEmail(text) == expected)
    }

    @Test(arguments: [
        ("#!/bin/bash\necho hi", true),
        ("func add(_ a: Int, _ b: Int) -> Int {\n    return a + b\n}", true),
        ("const x = require('x');\nmodule.exports = () => x;", true),
        ("def run(self):\n    return self.value\n", true),
        ("SELECT id, name FROM users WHERE id = 1;", true),
        ("#include <stdio.h>\nint main(void) {\n  return 0;\n}", true),
        ("<div class=\"a\">hello</div>", true),
        ("let total = items.map { $0.price }.reduce(0, +);", true),
        ("Meeting at noon, bring the notes and the budget.", false),
        ("Hello, this is a normal sentence. It has two sentences.", false),
        ("https://example.com/path?x=1;y=2", false),
        ("hello@example.com", false),
        ("#FF8800", false),
        ("Remember to buy milk (the organic kind).", false),
        ("short", false),
    ])
    func code(_ text: String, _ expected: Bool) {
        #expect(ClipboardClassifier.isCode(text) == expected, "\(text)")
    }

    @Test func pinboardMembership() {
        #expect(ClipboardPinboard.colors.matches(entry(.color, text: "#fff")))
        #expect(ClipboardPinboard.links.matches(entry(.link, text: "https://a.com")))
        #expect(!ClipboardPinboard.links.matches(entry(.text)))
        #expect(ClipboardPinboard.images.matches(entry(.image, text: nil)))
        #expect(ClipboardPinboard.files.matches(entry(.file, text: "/tmp/a")))
        #expect(ClipboardPinboard.emails.matches(entry(.text, text: "me@example.com")))
        #expect(!ClipboardPinboard.emails.matches(entry(.image, text: nil)))
        #expect(ClipboardPinboard.code.matches(entry(.text, text: "func f() {\n  return 1\n}")))
        #expect(!ClipboardPinboard.code.matches(entry(.link, text: "https://a.com")))
    }

    @Test func enabledPinboardsFollowSettings() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-pb-\(UUID())")!)
        #expect(ClipboardPinboard.enabled(in: settings) == [.code, .emails])
        settings.clipboardPinboards = ["links", "colors"]
        #expect(ClipboardPinboard.enabled(in: settings) == [.colors, .links])
    }
}

struct ClipboardLinkCleanerTests {
    @Test(arguments: [
        ("https://example.com/a?utm_source=x&utm_medium=y&id=7", "https://example.com/a?id=7"),
        ("https://example.com/a?utm_source=x", "https://example.com/a"),
        ("https://example.com/a?fbclid=abc#frag", "https://example.com/a#frag"),
        ("https://example.com/?gclid=1&q=swift&igshid=2", "https://example.com/?q=swift"),
        ("https://open.spotify.com/track/1?si=abc123", "https://open.spotify.com/track/1"),
        ("https://www.youtube.com/watch?v=abc&si=zzz", "https://www.youtube.com/watch?v=abc"),
        ("https://youtu.be/abc?si=zzz&t=30", "https://youtu.be/abc?t=30"),
        ("https://x.com/u/status/1?s=20&t=abc", "https://x.com/u/status/1"),
        ("https://github.com/o/r/blob/main/a.swift?ref=main", "https://github.com/o/r/blob/main/a.swift?ref=main"),
        ("https://example.com/a?si=keep&t=keep", "https://example.com/a?si=keep&t=keep"),
        ("https://www.amazon.com/dp/B0?ref=sr_1_1&psc=1&th=1", "https://www.amazon.com/dp/B0?th=1"),
        ("https://example.com/a?UTM_Campaign=x&MC_EID=1", "https://example.com/a"),
        ("https://example.com/a?q=a%20b&utm_term=t", "https://example.com/a?q=a%20b"),
        ("https://example.com/plain", "https://example.com/plain"),
        ("not a link ?utm_source=x", "not a link ?utm_source=x"),
        ("https://m.youtube.com/watch?v=1&feature=share", "https://m.youtube.com/watch?v=1"),
    ])
    func clean(_ input: String, _ expected: String) {
        #expect(ClipboardLinkCleaner.clean(input) == expected)
    }
}

struct ClipboardPolicyTests {
    @Test func limitKeepsNewestAndPinnedSurviveLimit() {
        let now = Date()
        let pinnedOld = entry(age: 9000, pinned: true, now: now)
        let recent = (0..<5).map { entry(age: Double($0) * 10, now: now) }
        let kept = ClipboardPolicy.retain(recent + [pinnedOld], now: now, limit: 3, maxBytes: 1000, keepFor: .forever)
        #expect(kept.count == 3)
        #expect(kept.first?.id == pinnedOld.id)
        #expect(kept.dropFirst().map(\.id) == recent.prefix(2).map(\.id))
    }

    @Test func retentionDropsOldUnpinnedOnly() {
        let now = Date()
        let old = entry(age: 8 * 86_400, now: now)
        let oldPinned = entry(age: 40 * 86_400, pinned: true, now: now)
        let fresh = entry(age: 3600, now: now)
        let all = [old, oldPinned, fresh]
        func ids(_ keep: ClipboardKeepFor) -> Set<UUID> {
            Set(ClipboardPolicy.retain(all, now: now, limit: 50, maxBytes: 1000, keepFor: keep).map(\.id))
        }
        #expect(ids(.day) == [oldPinned.id, fresh.id])
        #expect(ids(.week) == [oldPinned.id, fresh.id])
        #expect(ids(.month) == [oldPinned.id, old.id, fresh.id])
        #expect(ids(.forever) == [oldPinned.id, old.id, fresh.id])
    }

    @Test func byteCapAppliesEvenWithoutCountLimit() {
        let now = Date()
        let items = (0..<4).map { entry(age: Double($0), bytes: 40, now: now) }
        let kept = ClipboardPolicy.retain(items, now: now, limit: .max, maxBytes: 100, keepFor: .forever)
        #expect(kept.count == 2)
    }

    @Test func retainNeverMutatesInput() {
        let items = [entry(age: 5), entry(age: 1)]
        let copy = items
        _ = ClipboardPolicy.retain(items, limit: 1, maxBytes: 100, keepFor: .day)
        #expect(items == copy)
    }

    @Test func displayOrderPlacesPinnedFirstOrByDate() {
        let now = Date()
        let a = entry(age: 30, pinned: true, now: now), b = entry(age: 10, now: now), c = entry(age: 20, now: now)
        func order(_ placement: ClipboardPinnedPlacement) -> [UUID] {
            ClipboardPolicy.displayOrder([a, b, c], date: \.date, pinned: \.isPinned, placement: placement).map(\.id)
        }
        #expect(order(.beforeRecent) == [a.id, b.id, c.id])
        #expect(order(.dateOrder) == [b.id, c.id, a.id])
    }

    @Test func skipRulesRespectSettings() {
        var policy = ClipboardPolicy()
        let concealed = ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"]
        #expect(policy.shouldSkip(types: concealed, frontmost: nil))
        #expect(policy.shouldSkip(types: ["public.utf8-plain-text"], frontmost: "com.1password.1password"))
        #expect(!policy.shouldSkip(types: ["public.utf8-plain-text"], frontmost: "com.apple.Safari"))
        policy.excludedApps = ["com.apple.Safari"]
        #expect(policy.shouldSkip(types: ["public.utf8-plain-text"], frontmost: "com.apple.Safari"))
        policy.skipSensitive = false
        #expect(!policy.shouldSkip(types: concealed, frontmost: "com.bitwarden.desktop"))
        // Brim's own markers are skipped regardless.
        #expect(policy.shouldSkip(types: ["io.github.cezarprox.brim.clipboard-replay"], frontmost: nil))
    }

    @Test func autoClearDecision() {
        #expect(!ClipboardAutoClear.shouldSchedule(seconds: 0, onlySensitive: false, sensitive: true))
        #expect(ClipboardAutoClear.shouldSchedule(seconds: 30, onlySensitive: false, sensitive: false))
        #expect(!ClipboardAutoClear.shouldSchedule(seconds: 30, onlySensitive: true, sensitive: false))
        #expect(ClipboardAutoClear.shouldSchedule(seconds: 30, onlySensitive: true, sensitive: true))
    }

    @Test func settingsDefaultsAndClamping() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-cs-\(UUID())")!)
        #expect(settings.clipboardHistoryLimit == 100)
        #expect(settings.clipboardSkipPasswords && settings.clipboardRejectDuplicates)
        #expect(settings.clipboardKeepFor == .forever)
        settings.clipboardHistoryLimit = 5_000
        #expect(settings.clipboardHistoryLimit == 500)
        settings.clipboardHistoryLimit = 0
        #expect(ClipboardPolicy(settings: settings).limit == nil)
    }
}

@MainActor
struct ClipboardStorePolicyTests {
    private func make(_ configure: (AppSettings) -> Void = { _ in }, frontmost: String? = nil)
        -> (ClipboardStore, NSPasteboard, AppSettings) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-st-\(UUID())")!)
        configure(settings)
        let board = NSPasteboard(name: .init(UUID().uuidString))
        let store = ClipboardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                   pasteboard: board, settings: settings, frontmostApp: { frontmost })
        store.start()
        return (store, board, settings)
    }

    private func copy(_ text: String, to board: NSPasteboard, store: ClipboardStore, extra: [String] = []) async {
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for type in extra { item.setData(Data(), forType: .init(type)) }
        board.writeObjects([item])
        await store.captureChange()
    }

    @Test func duplicatesMoveToTopByDefaultAndStackWhenAllowed() async {
        let (store, board, _) = make()
        for text in ["a", "b", "a"] { await copy(text, to: board, store: store) }
        #expect(store.entries.map(\.text) == ["a", "b"])
        #expect(store.entries.first?.copies == 2)

        let (twin, board2, _) = make { $0.clipboardRejectDuplicates = false }
        for text in ["a", "b", "a"] { await copy(text, to: board2, store: twin) }
        #expect(twin.entries.map(\.text) == ["a", "b", "a"])
    }

    @Test func concealedItemsAreSkippedOnlyWhileSkipPasswordsIsOn() async {
        let (store, board, _) = make()
        await copy("secret", to: board, store: store, extra: ["org.nspasteboard.ConcealedType"])
        #expect(store.entries.isEmpty)
        let (open, board2, _) = make { $0.clipboardSkipPasswords = false }
        await copy("secret", to: board2, store: open, extra: ["org.nspasteboard.ConcealedType"])
        #expect(open.entries.map(\.text) == ["secret"])
    }

    @Test func passwordManagerAndExcludedAppsAreSkipped() async {
        let (manager, board, _) = make(frontmost: "com.bitwarden.desktop")
        await copy("hunter2", to: board, store: manager)
        #expect(manager.entries.isEmpty)
        let (excluded, board2, _) = make({ $0.clipboardExcludedApps = ["com.example.Private"] }, frontmost: "com.example.Private")
        await copy("hello", to: board2, store: excluded)
        #expect(excluded.entries.isEmpty)
    }

    @Test func limitSettingPrunesExistingHistory() async {
        let (store, board, settings) = make()
        for index in 0..<15 { await copy("item \(index)", to: board, store: store) }
        #expect(store.entries.count == 15)
        settings.clipboardHistoryLimit = 10
        store.pruneExpired()
        #expect(store.entries.count == 10)
        #expect(store.entries.first?.text == "item 14")
    }

    @Test func linksAreCleanedOnCopyAndOptionallyOnCapture() async {
        let dirty = "https://example.com/a?utm_source=x&id=1"
        let (store, board, _) = make()
        await copy(dirty, to: board, store: store)
        #expect(store.entries.first?.text == dirty)
        let entry = try! #require(store.entries.first)
        #expect(store.copy(entry))
        #expect(board.string(forType: .string) == "https://example.com/a?id=1")

        let (eager, board2, _) = make { $0.clipboardCleanLinksOnCapture = true }
        await copy(dirty, to: board2, store: eager)
        #expect(eager.entries.first?.text == "https://example.com/a?id=1")

        let (keep, board3, _) = make { $0.clipboardCleanLinksOnCopy = false }
        await copy(dirty, to: board3, store: keep)
        #expect(keep.copy(keep.entries[0]))
        #expect(board3.string(forType: .string) == dirty)
    }

    @Test func autoClearEmptiesPasteboardButKeepsHistory() async throws {
        let (store, board, _) = make { $0.clipboardAutoClearSeconds = 1 }
        await copy("temporary", to: board, store: store)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(board.string(forType: .string) == nil)
        #expect(store.entries.map(\.text) == ["temporary"])
    }

    @Test func autoClearLeavesNewerCopiesAlone() async throws {
        let (store, board, _) = make { $0.clipboardAutoClearSeconds = 1 }
        await copy("first", to: board, store: store)
        board.clearContents()
        board.setString("second", forType: .string)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(board.string(forType: .string) == "second")
    }

    @Test func clearOnQuitKeepsPinned() async {
        let (store, board, settings) = make { $0.clipboardClearOnQuit = true }
        await copy("keep", to: board, store: store)
        await copy("drop", to: board, store: store)
        _ = store.setPinned(store.entries.first { $0.text == "keep" }!, true)
        store.prepareForQuit()
        #expect(store.entries.map(\.text) == ["keep"])
        settings.clipboardClearOnQuit = false
    }

    @Test func importAddsNewTextOnceAndSkipsKnownContent() async {
        let (store, board, _) = make()
        await copy("already", to: board, store: store)
        let items = [
            ClipboardImportItem(text: "already", date: .now, copies: 1, isPinned: false, sourceApp: nil),
            ClipboardImportItem(text: "https://a.com", date: .now.addingTimeInterval(-60), copies: 3, isPinned: true, sourceApp: nil),
        ]
        #expect(store.importItems(items) == 1)
        #expect(store.importItems(items) == 0)
        #expect(store.entries.contains { $0.kind == .link && $0.isPinned && $0.copies == 3 })
    }
}

struct ClipboardMaccyImporterTests {
    private func fixture(rows: [(title: String, blob: String?, last: Double, copies: Int, pin: String?)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("maccy-\(UUID()).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let schema = """
            CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZLASTCOPIEDAT TIMESTAMP,
                ZNUMBEROFCOPIES INTEGER, ZPIN VARCHAR, ZAPPLICATION VARCHAR);
            CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
            """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        for (index, row) in rows.enumerated() {
            let pin = row.pin.map { "'\($0)'" } ?? "NULL"
            #expect(sqlite3_exec(db, "INSERT INTO ZHISTORYITEM VALUES (\(index + 1), '\(row.title)', \(row.last), \(row.copies), \(pin), 'Safari')", nil, nil, nil) == SQLITE_OK)
            if let blob = row.blob {
                #expect(sqlite3_exec(db, "INSERT INTO ZHISTORYITEMCONTENT VALUES (\(index + 1), \(index + 1), 'public.utf8-plain-text', CAST('\(blob)' AS BLOB))", nil, nil, nil) == SQLITE_OK)
            }
        }
        return url
    }

    @Test func readsTextNewestFirstWithPinsAndFallsBackToTitle() throws {
        let url = try fixture(rows: [
            (title: "old", blob: "old body", last: 100, copies: 2, pin: nil),
            (title: "titled only", blob: nil, last: 300, copies: 1, pin: "b"),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let items = try ClipboardMaccyImporter.readItems(at: url, limit: 10)
        #expect(items.map(\.text) == ["titled only", "old body"])
        #expect(items[0].isPinned && !items[1].isPinned)
        #expect(items[1].copies == 2)
        #expect(items[1].date == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test func missingStoreIsReportedNotThrown() {
        let result = ClipboardMaccyImporter.importHistory(from: [URL(fileURLWithPath: "/nonexistent/Storage.sqlite")])
        guard case .unavailable = result else { Issue.record("expected unavailable"); return }
    }

    @Test func wrongSchemaThrowsUnexpectedFormat() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID()).sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE other (a)", nil, nil, nil)
        sqlite3_close(db)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ClipboardMaccyImporter.ImportError.self) { try ClipboardMaccyImporter.readItems(at: url, limit: 5) }
    }
}
