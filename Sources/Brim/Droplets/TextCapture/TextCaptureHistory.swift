// TextCaptureHistory.swift
// Brim
//
// The last 100 captures, kept in Application Support (local only).

import Foundation

struct TextCaptureEntry: Codable, Identifiable, Equatable {
  enum Source: String, Codable { case area, image, pdf }
  enum Kind: String, Codable { case text, code }
  let id: UUID
  let date: Date
  let kind: Kind
  let source: Source
  let text: String
  /// Barcode symbology, or nil for recognized text.
  let symbology: String?
  let pages: Int?

  init(id: UUID = UUID(), date: Date = .now, kind: Kind, source: Source, text: String, symbology: String? = nil, pages: Int? = nil) {
    self.id = id; self.date = date; self.kind = kind; self.source = source
    self.text = text; self.symbology = symbology; self.pages = pages
  }

  var firstLine: String { text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text }
}

enum TextCaptureHistoryPolicy {
  static let limit = 100

  /// New entry first, identical text collapsed, capped at `limit`.
  static func adding(_ entry: TextCaptureEntry, to entries: [TextCaptureEntry]) -> [TextCaptureEntry] {
    let rest = entries.filter { !($0.text == entry.text && $0.kind == entry.kind) }
    return Array(([entry] + rest).prefix(limit))
  }

  static func search(_ entries: [TextCaptureEntry], query: String) -> [TextCaptureEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return entries }
    return entries.filter { $0.text.localizedCaseInsensitiveContains(needle) }
  }
}

@MainActor
final class TextCaptureHistory: ObservableObject {
  static let shared = TextCaptureHistory()
  @Published private(set) var entries: [TextCaptureEntry] = []
  private let file: URL

  init(file: URL? = nil) {
    self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/TextCapture/history.json")
    if let data = try? Data(contentsOf: self.file),
      let decoded = try? JSONDecoder().decode([TextCaptureEntry].self, from: data) {
      entries = Array(decoded.prefix(TextCaptureHistoryPolicy.limit))
    }
  }

  func add(_ entry: TextCaptureEntry) {
    entries = TextCaptureHistoryPolicy.adding(entry, to: entries)
    save()
  }

  func remove(_ entry: TextCaptureEntry) {
    entries.removeAll { $0.id == entry.id }
    save()
  }

  func clear() {
    entries = []
    save()
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(entries).write(to: file, options: .atomic)
    } catch {
      NSLog("Brim: couldn’t save Text Capture history: %@", error.localizedDescription)
    }
  }
}
