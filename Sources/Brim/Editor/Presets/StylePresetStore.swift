// StylePresetStore.swift
// Brim
//
// Saved canvas looks ("presets"): a name plus a `CanvasStyle` (background,
// padding, shadow, corners, aspect, alignment). One preset can be marked as
// the default that every newly opened screenshot starts with. Persisted as
// one small JSON file in Application Support; the recording module can keep
// its own store by passing a different file URL.

import Foundation
import os

struct StylePreset: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var style: CanvasStyle

    init(id: UUID = UUID(), name: String, style: CanvasStyle) {
        self.id = id
        self.name = name
        self.style = style
    }
}

struct StylePresetLibrary: Codable, Equatable, Sendable {
    var presets: [StylePreset] = []
    var defaultPresetID: UUID?

    var defaultPreset: StylePreset? {
        guard let defaultPresetID else { return nil }
        return presets.first { $0.id == defaultPresetID }
    }
}

@MainActor
final class StylePresetStore: ObservableObject {
    static let shared = StylePresetStore(fileURL: StylePresetStore.defaultFileURL)
    static let maxNameLength = 40

    @Published private(set) var library: StylePresetLibrary
    let fileURL: URL
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "StylePresets")

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Brim/EditorStylePresets.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.library = Self.load(from: fileURL)
    }

    var presets: [StylePreset] { library.presets }

    /// The style a new screenshot starts with: the default preset's look, or none.
    var styleForNewCapture: CanvasStyle? { library.defaultPreset?.style }

    @discardableResult
    func save(name: String, style: CanvasStyle) -> StylePreset {
        let preset = StylePreset(name: Self.sanitized(name, fallbackIndex: library.presets.count + 1), style: style)
        update { $0.presets.append(preset) }
        return preset
    }

    func rename(id: UUID, to name: String) {
        update { library in
            guard let index = library.presets.firstIndex(where: { $0.id == id }) else { return }
            library.presets[index].name = Self.sanitized(name, fallbackIndex: index + 1)
        }
    }

    func replaceStyle(id: UUID, with style: CanvasStyle) {
        update { library in
            guard let index = library.presets.firstIndex(where: { $0.id == id }) else { return }
            library.presets[index].style = style
        }
    }

    func delete(id: UUID) {
        update { library in
            library.presets.removeAll { $0.id == id }
            if library.defaultPresetID == id { library.defaultPresetID = nil }
        }
    }

    /// Marks a preset as the look for every new screenshot (nil clears it).
    func setDefault(id: UUID?) {
        update { library in
            library.defaultPresetID = id.flatMap { id in library.presets.contains { $0.id == id } ? id : nil }
        }
    }

    // MARK: - Persistence

    private func update(_ change: (inout StylePresetLibrary) -> Void) {
        var next = library
        change(&next)
        guard next != library else { return }
        library = next
        persist(next)
    }

    private func persist(_ library: StylePresetLibrary) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(library).write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("Could not save style presets: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func load(from url: URL) -> StylePresetLibrary {
        guard let data = try? Data(contentsOf: url) else { return StylePresetLibrary() }
        do {
            return try JSONDecoder().decode(StylePresetLibrary.self, from: data)
        } catch {
            log.error("Ignoring unreadable style presets: \(error.localizedDescription, privacy: .public)")
            return StylePresetLibrary()
        }
    }

    static func sanitized(_ name: String, fallbackIndex: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .controlCharacters).joined()
        guard !trimmed.isEmpty else { return L10n.tr("Preset %lld", fallbackIndex) }
        return String(trimmed.prefix(maxNameLength))
    }
}
