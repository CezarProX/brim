// ClipboardMaccyImporter.swift
// Brim
//
// Best-effort, read-only import of Maccy's history. Maccy keeps a Core Data SQLite store
// (ZHISTORYITEM / ZHISTORYITEMCONTENT). The store is copied to a temporary folder first so
// the original, and its WAL, are never opened for writing. If the file is missing or macOS
// denies access (sandboxed container), the import reports that and does nothing.

import Foundation
import SQLite3

struct ClipboardImportItem: Equatable, Sendable {
    let text: String
    let date: Date
    let copies: Int
    let isPinned: Bool
    let sourceApp: String?
}

enum ClipboardImportResult: Equatable {
    case unavailable(String)
    case items([ClipboardImportItem])
}

enum ClipboardMaccyImporter {
    /// Where Maccy keeps its store (sandboxed App Store build first, then the direct download).
    static var candidateStores: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite",
            "Library/Application Support/Maccy/Storage.sqlite",
        ].map { home.appendingPathComponent($0) }
    }

    static func importHistory(from candidates: [URL] = candidateStores, limit: Int = 500) -> ClipboardImportResult {
        let fm = FileManager.default
        guard let store = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            return .unavailable("Maccy’s history wasn’t found on this Mac.")
        }
        let scratch = fm.temporaryDirectory.appendingPathComponent("Brim-MaccyImport-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let copy = scratch.appendingPathComponent("Storage.sqlite")
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: store.path + suffix)
                if fm.fileExists(atPath: source.path) {
                    try fm.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
            return .items(try readItems(at: copy, limit: limit))
        } catch {
            return .unavailable("Maccy’s history couldn’t be read (\(error.localizedDescription)). "
                + "Grant Brim Full Disk Access to import it.")
        }
    }

    /// Reads text items from a Maccy-shaped database. Internal so tests can build a fixture.
    static func readItems(at url: URL, limit: Int) throws -> [ClipboardImportItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw ImportError.cannotOpen
        }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT i.ZTITLE, i.ZLASTCOPIEDAT, i.ZNUMBEROFCOPIES, i.ZPIN, i.ZAPPLICATION,
                   (SELECT c.ZVALUE FROM ZHISTORYITEMCONTENT c WHERE c.ZITEM = i.Z_PK
                      AND c.ZTYPE IN ('public.utf8-plain-text', 'NSStringPboardType') LIMIT 1)
            FROM ZHISTORYITEM i ORDER BY i.ZLASTCOPIEDAT DESC LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ImportError.unexpectedSchema
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var items: [ClipboardImportItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let body = blobString(statement, 5) ?? columnString(statement, 0)
            guard let text = body, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // Core Data timestamps count seconds from 2001-01-01.
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1))
            let pin = columnString(statement, 3)
            items.append(ClipboardImportItem(
                text: text, date: date, copies: max(1, Int(sqlite3_column_int(statement, 2))),
                isPinned: !(pin ?? "").isEmpty, sourceApp: nil))
        }
        return items
    }

    private static func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private static func blobString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB || sqlite3_column_type(statement, index) == SQLITE_TEXT,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return String(data: Data(bytes: bytes, count: count), encoding: .utf8)
    }

    enum ImportError: LocalizedError {
        case cannotOpen, unexpectedSchema
        var errorDescription: String? {
            switch self {
            case .cannotOpen: return "the database couldn’t be opened"
            case .unexpectedSchema: return "its format isn’t one Brim recognizes"
            }
        }
    }
}
