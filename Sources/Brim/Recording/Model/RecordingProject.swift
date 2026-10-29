// RecordingProject.swift
// Brim
//
// One folder per recording (`<Recordings>/<id>.qsrec/`) holding the raw capture, the pointer
// track, capture metadata and the edit. Nothing here touches the user's save folder: exports are
// written there separately, so the project can be re-edited later.

import CoreGraphics
import Foundation

struct RecordingMetadata: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case display, window, area, imported }

    var version = 1
    var id: UUID
    var createdAt: Date
    var title: String
    var source: Source
    /// Encoded video size.
    var pixelWidth: Int
    var pixelHeight: Int
    /// Captured area in points (pointer size and click ripples scale from this).
    var pointWidth: Double
    var pointHeight: Double
    var fps: Int
    var duration: Double
    var hasSystemAudio: Bool
    var hasMicrophone: Bool

    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    var pointSize: CGSize { CGSize(width: pointWidth, height: pointHeight) }
    /// Video pixels per captured point (2 on Retina at full resolution).
    var pixelsPerPoint: Double { pointHeight > 0 ? Double(pixelHeight) / pointHeight : 1 }
}

struct RecordingProject: Equatable, Sendable {
    static let folderExtension = "qsrec"

    let folder: URL

    var videoURL: URL { folder.appendingPathComponent("recording.mov") }
    var cursorURL: URL { folder.appendingPathComponent("cursor.json") }
    var metadataURL: URL { folder.appendingPathComponent("project.json") }
    var editURL: URL { folder.appendingPathComponent("edit.json") }
    var id: String { folder.deletingPathExtension().lastPathComponent }

    /// Creates an empty project folder under `root`.
    static func create(in root: URL, id: UUID = UUID()) throws -> RecordingProject {
        let folder = root.appendingPathComponent("\(id.uuidString).\(folderExtension)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return RecordingProject(folder: folder)
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func save(_ metadata: RecordingMetadata) throws { try write(metadata, to: metadataURL) }
    func save(_ track: CursorTrack) throws { try write(track, to: cursorURL) }
    func save(_ edit: StudioEdit) throws { try write(edit, to: editURL) }

    func loadMetadata() throws -> RecordingMetadata { try read(RecordingMetadata.self, from: metadataURL) }

    /// A missing or unreadable track is not fatal: the video is still editable without a pointer.
    func loadTrack() -> CursorTrack { (try? read(CursorTrack.self, from: cursorURL)) ?? .empty }

    func loadEdit() -> StudioEdit? { try? read(StudioEdit.self, from: editURL) }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try Self.decoder.decode(type, from: Data(contentsOf: url))
    }
}

enum RecordingLibrary {
    /// `~/Library/Application Support/Brim/Recordings`.
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Brim/Recordings", isDirectory: true)
    }

    /// Saved projects, newest first.
    static func projects(in root: URL = root) -> [(RecordingProject, RecordingMetadata)] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.pathExtension == RecordingProject.folderExtension }
            .compactMap { folder in
                let project = RecordingProject(folder: folder)
                guard let metadata = try? project.loadMetadata() else { return nil }
                return (project, metadata)
            }
            .sorted { $0.1.createdAt > $1.1.createdAt }
    }

    /// "Recording 2026-10-26 at 14.03.11" — matches macOS' own naming.
    static func title(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(L10n.tr("Recording")) \(formatter.string(from: date))"
    }
}
