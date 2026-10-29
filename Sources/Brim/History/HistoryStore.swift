// HistoryStore.swift
// Brim
//
// Persists a lightweight record of past saves / uploads / clipboard captures
// as JSON under Application Support, so the "Screenshot History" and "Upload
// History" menu items have something to show.

import Foundation

/// A single recorded capture event (save, upload, or clipboard-only copy).
struct HistoryEntry: Codable, Identifiable, Equatable {

    /// The kind of terminal action that produced this entry.
    enum Kind: String, Codable {
        case save
        case upload
        case clipboard
    }

    let id: UUID
    let date: Date
    let kind: Kind
    /// Where the file was written, if this entry came from a save.
    let fileURL: URL?
    /// The uploaded link, if this entry came from an upload.
    let link: URL?
    /// Human-readable pixel dimensions, e.g. "1920x1080".
    let pixelSize: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        fileURL: URL? = nil,
        link: URL? = nil,
        pixelSize: String
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.fileURL = fileURL
        self.link = link
        self.pixelSize = pixelSize
    }
}

/// JSON-file-backed store for `HistoryEntry` records.
///
/// All access happens on the main actor: history is only ever mutated from
/// user-initiated actions (save/upload/copy) and read back for a small UI
/// list, so there's no need for a background-queue file-access design.
@MainActor
final class HistoryStore {

    static let shared = HistoryStore()

    private let fileURL: URL
    private var cachedEntries: [HistoryEntry]

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolvedURL
        self.cachedEntries = Self.load(from: resolvedURL)
    }

    // MARK: - Public API

    /// Appends a new entry and persists the updated history to disk.
    func add(_ entry: HistoryEntry) {
        cachedEntries.append(entry)
        persist()
    }

    /// Records a clipboard-only capture, but only if the user has opted in
    /// via `AppSettings.saveHistoryOfClipboardCaptures` — callers don't need
    /// to check the setting themselves.
    func recordClipboardCapture(size: String) {
        guard AppSettings.shared.saveHistoryOfClipboardCaptures else { return }
        add(HistoryEntry(kind: .clipboard, pixelSize: size))
    }

    /// Returns entries of the given kind (most recent first), or all entries
    /// if `kind` is `nil`.
    func entries(kind: HistoryEntry.Kind? = nil) -> [HistoryEntry] {
        let filtered = kind.map { k in cachedEntries.filter { $0.kind == k } } ?? cachedEntries
        return filtered.sorted { $0.date > $1.date }
    }

    /// Removes all recorded history from memory and disk.
    func clear() {
        cachedEntries = []
        persist()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = appSupport.appendingPathComponent("Brim", isDirectory: true)
        return directory.appendingPathComponent("history.json")
    }

    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(cachedEntries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Brim: failed to persist history to \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
