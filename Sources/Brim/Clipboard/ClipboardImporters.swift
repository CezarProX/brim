// ClipboardImporters.swift
// Brim
//
// Best-effort, read-only importers for Raycast, Clipy and Paste. None of these apps documents its
// on-disk format, so each reader sniffs what it finds, copies the files to a scratch folder before
// opening them, and reports plainly when the history is missing, encrypted or unrecognised.
// Nothing is ever written to the other app's files.

import Foundation
import SQLite3

enum ClipboardImportSource: String, CaseIterable, Identifiable {
    case maccy, clipy, raycast, paste
    var id: String { rawValue }
    var title: String {
        switch self {
        case .maccy: return "Maccy"
        case .clipy: return "Clipy"
        case .raycast: return "Raycast"
        case .paste: return "Paste"
        }
    }
}

enum ClipboardImporters {
    static func importHistory(from source: ClipboardImportSource, limit: Int = 500) -> ClipboardImportResult {
        switch source {
        case .maccy: return ClipboardMaccyImporter.importHistory(limit: limit)
        case .clipy: return ClipyImporter.importHistory(limit: limit)
        case .raycast: return SniffingSQLiteImporter.importHistory(
            name: "Raycast", folders: SniffingSQLiteImporter.raycastFolders, limit: limit)
        case .paste: return SniffingSQLiteImporter.importHistory(
            name: "Paste", folders: SniffingSQLiteImporter.pasteFolders, limit: limit)
        }
    }

    /// Core Data stores seconds since 2001; most others use Unix seconds or milliseconds.
    static func date(from raw: Double) -> Date {
        if raw > 1e11 { return Date(timeIntervalSince1970: raw / 1000) }
        if raw > 1.2e9 { return Date(timeIntervalSince1970: raw) }
        if raw > 0 { return Date(timeIntervalSinceReferenceDate: raw) }
        return Date()
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
}

// MARK: - Schema sniffing

struct ImportTableShape: Equatable {
    let name: String
    let columns: [String]
}

struct ImportSchemaGuess: Equatable {
    let table: String
    let textColumn: String
    let dateColumn: String?
}

enum ImportSchemaSniffer {
    private static let textNames = ["ztext", "zstring", "zplaintext", "zvalue", "zcontent", "plain_text", "plaintext",
                                    "text", "string", "content", "value", "title"]
    private static let dateHints = ["date", "time", "created", "copied", "stamp"]

    /// The table that most plausibly holds copied text: best text-column name wins, ties go to the
    /// table whose name mentions clips, history or items.
    static func choose(_ tables: [ImportTableShape]) -> ImportSchemaGuess? {
        var best: (score: Int, guess: ImportSchemaGuess)?
        for table in tables {
            let lowered = table.columns.map { ($0, $0.lowercased()) }
            guard let text = textNames.enumerated().compactMap({ index, name in
                lowered.first { $0.1 == name }.map { ($0.0, textNames.count - index) }
            }).first else { continue }
            let date = lowered.first { column in dateHints.contains { column.1.contains($0) } }?.0
            let name = table.name.lowercased()
            let bonus = ["clip", "history", "item", "entry"].contains { name.contains($0) } ? 5 : 0
            let score = text.1 + bonus + (date == nil ? 0 : 2)
            if best == nil || score > best!.score {
                best = (score, ImportSchemaGuess(table: table.name, textColumn: text.0, dateColumn: date))
            }
        }
        return best?.guess
    }
}

enum SniffingSQLiteImporter {
    static var raycastFolders: [URL] {
        [ClipboardImporters.home.appendingPathComponent("Library/Application Support/com.raycast.macos")]
    }
    static var pasteFolders: [URL] {
        let home = ClipboardImporters.home
        return ["Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste",
                "Library/Application Support/Paste"].map { home.appendingPathComponent($0) }
    }

    static func importHistory(name: String, folders: [URL], limit: Int) -> ClipboardImportResult {
        let candidates = databases(in: folders)
        guard !candidates.isEmpty else { return .unavailable("\(name)’s history wasn’t found on this Mac.") }
        for database in candidates {
            if let items = try? readCopy(of: database, limit: limit), !items.isEmpty { return .items(items) }
        }
        return .unavailable("\(name) keeps its history in a protected or unrecognised format, so it can’t be imported.")
    }

    /// SQLite files (by header) directly in the folders or one level down.
    static func databases(in folders: [URL], files: FileManager = .default) -> [URL] {
        var found: [URL] = []
        for folder in folders {
            let entries = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                var isDirectory: ObjCBool = false
                files.fileExists(atPath: entry.path, isDirectory: &isDirectory)
                let nested = isDirectory.boolValue ? ((try? files.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []) : [entry]
                found += nested.filter(hasSQLiteHeader)
            }
        }
        return found
    }

    static func hasSQLiteHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 15)).map { String(decoding: $0, as: UTF8.self) == "SQLite format 3" } ?? false
    }

    private static func readCopy(of database: URL, limit: Int) throws -> [ClipboardImportItem] {
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent("Brim-Import-\(UUID().uuidString)")
        defer { try? files.removeItem(at: scratch) }
        try files.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let copy = scratch.appendingPathComponent("store.sqlite")
        for suffix in ["", "-wal", "-shm"] where files.fileExists(atPath: database.path + suffix) {
            try files.copyItem(at: URL(fileURLWithPath: database.path + suffix), to: URL(fileURLWithPath: copy.path + suffix))
        }
        return try readItems(at: copy, limit: limit)
    }

    /// Reads the most plausible text table of any SQLite file. Internal so tests can build a fixture.
    static func readItems(at url: URL, limit: Int) throws -> [ClipboardImportItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw ClipboardMaccyImporter.ImportError.cannotOpen
        }
        defer { sqlite3_close(db) }
        let tables = try shapes(db)
        guard let guess = ImportSchemaSniffer.choose(tables) else { throw ClipboardMaccyImporter.ImportError.unexpectedSchema }
        let order = guess.dateColumn.map { " ORDER BY \(quoted($0)) DESC" } ?? ""
        let dateSelect = guess.dateColumn.map(quoted) ?? "0"
        let sql = "SELECT \(quoted(guess.textColumn)), \(dateSelect) FROM \(quoted(guess.table))\(order) LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ClipboardMaccyImporter.ImportError.unexpectedSchema
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var items: [ClipboardImportItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = string(statement, 0), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            items.append(ClipboardImportItem(text: text, date: ClipboardImporters.date(from: sqlite3_column_double(statement, 1)),
                                             copies: 1, isPinned: false, sourceApp: nil))
        }
        return items
    }

    private static func shapes(_ db: OpaquePointer) throws -> [ImportTableShape] {
        var names: [String] = []
        try query(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") { names.append(string($0, 0) ?? "") }
        return try names.filter { !$0.isEmpty }.map { name in
            var columns: [String] = []
            try query(db, "PRAGMA table_info(\(quoted(name)))") { columns.append(string($0, 1) ?? "") }
            return ImportTableShape(name: name, columns: columns)
        }
    }

    private static func query(_ db: OpaquePointer, _ sql: String, row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ClipboardMaccyImporter.ImportError.unexpectedSchema
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    private static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        if sqlite3_column_type(statement, index) == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, index) {
            return String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))), encoding: .utf8)
        }
        return sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
