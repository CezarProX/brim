import AppKit
import Combine
import ImageIO

struct ShelfEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let pixelSize: String
}

/// Owns only the private shelf cache. Main-actor isolation serializes mutations.
/// Callers should vend PNG data for dragging, since cached files can be evicted.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var entries: [ShelfEntry] = []
    @Published private(set) var errorMessage: String?

    private let directory: URL
    private let maxCount: Int
    private let maxBytes: Int
    private let files = FileManager.default
    private var thumbnails: [UUID: NSImage] = [:]
    private var metadataURL: URL { directory.appendingPathComponent("entries.json") }

    init(directory: URL? = nil, maxCount: Int = 20, maxBytes: Int = 150 * 1024 * 1024) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Brim/Shelf", isDirectory: true)
        self.maxCount = max(1, maxCount)
        self.maxBytes = max(1, maxBytes)
        do {
            try prepareDirectory()
            if files.fileExists(atPath: metadataURL.path) {
                let decoded = try JSONDecoder().decode([ShelfEntry].self, from: Data(contentsOf: metadataURL))
                var seen = Set<UUID>()
                entries = try bounded(decoded.filter {
                    seen.insert($0.id).inserted && files.fileExists(atPath: fileURL(for: $0).path)
                }.sorted { $0.date > $1.date })
                try persist(entries)
            }
            try cleanUnusedFiles()
        } catch {
            report(error)
            // The index is unreadable but the screenshots are still on disk: rebuild it from them
            // rather than let the next capture's cleanup delete every one.
            entries = recoveredEntries()
        }
    }

    /// Entries for the screenshots in the folder, newest first, when the index can't be read.
    private func recoveredEntries() -> [ShelfEntry] {
        let urls = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let recovered: [ShelfEntry] = urls.compactMap { url in
            guard url.pathExtension == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let size = NSImage(contentsOf: url).map(ImageEncoder.pixelSizeString(of:)) ?? ""
            return ShelfEntry(id: id, date: date, pixelSize: size)
        }
        return Array(recovered.sorted { $0.date > $1.date }.prefix(maxCount))
    }

    func add(_ image: NSImage, id: UUID) {
        errorMessage = nil
        let entry = ShelfEntry(id: id, date: Date(), pixelSize: ImageEncoder.pixelSizeString(of: image))
        do {
            let png = try ImageEncoder.pngDataPreservingAlpha(from: image)
            let preview = try Self.thumbnailData(png)
            guard png.count + preview.count <= maxBytes else { throw StoreError.tooLarge }
            try prepareDirectory()
            let oldPNG = try readIfPresent(fileURL(for: entry))
            let oldPreview = try readIfPresent(thumbnailURL(entry))
            do {
                try writePrivate(png, to: fileURL(for: entry))
                try writePrivate(preview, to: thumbnailURL(entry))
                let updated = try bounded([entry] + entries.filter { $0.id != id })
                try persist(updated)
                thumbnails[id] = NSImage(data: preview)
                entries = updated
            } catch {
                try restore(oldPNG, to: fileURL(for: entry))
                try restore(oldPreview, to: thumbnailURL(entry))
                throw error
            }
            try cleanUnusedFiles()
        } catch {
            report(error)
        }
    }

    func remove(_ entry: ShelfEntry) {
        update(entries.filter { $0.id != entry.id })
    }

    func clear() {
        update([])
    }

    func image(for entry: ShelfEntry) -> NSImage? {
        guard let result = NSImage(contentsOf: fileURL(for: entry)) else {
            report(StoreError.missingImage)
            return nil
        }
        return result
    }

    func thumbnail(for entry: ShelfEntry) -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        guard let image = NSImage(contentsOf: thumbnailURL(entry)) else {
            // This getter is used while SwiftUI renders; never publish here.
            return nil
        }
        thumbnails[entry.id] = image
        return image
    }

    func fileURL(for entry: ShelfEntry) -> URL {
        directory.appendingPathComponent("\(entry.id.uuidString).png")
    }

    private func thumbnailURL(_ entry: ShelfEntry) -> URL {
        directory.appendingPathComponent("\(entry.id.uuidString)-thumb.png")
    }

    private func update(_ updated: [ShelfEntry]) {
        errorMessage = nil
        do {
            try persist(updated)
            entries = updated
            try cleanUnusedFiles()
        } catch {
            report(error)
        }
    }

    private func prepareDirectory() throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func persist(_ updated: [ShelfEntry]) throws {
        try writePrivate(JSONEncoder().encode(updated), to: metadataURL)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        files.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    private func restore(_ data: Data?, to url: URL) throws {
        if let data { try writePrivate(data, to: url) }
        else if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    private func bounded(_ candidates: [ShelfEntry]) throws -> [ShelfEntry] {
        var bytes = 0
        var result: [ShelfEntry] = []
        for entry in candidates.prefix(maxCount) {
            let urls = [fileURL(for: entry), thumbnailURL(entry)]
            let size = try urls.reduce(0) { total, url in
                guard files.fileExists(atPath: url.path) else { return total }
                let attributes = try files.attributesOfItem(atPath: url.path)
                return total + ((attributes[.size] as? NSNumber)?.intValue ?? 0)
            }
            guard size <= maxBytes - bytes else { break }
            bytes += size
            result.append(entry)
        }
        return result
    }

    /// UUID-only ownership checks keep unrelated files and user originals untouched.
    private func cleanUnusedFiles() throws {
        let retained = Set(entries.map(\.id))
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard url.pathExtension == "png" else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let identifier = name.hasSuffix("-thumb") ? String(name.dropLast(6)) : name
            guard let id = UUID(uuidString: identifier), !retained.contains(id) else { continue }
            try files.removeItem(at: url)
        }
    }

    private static func thumbnailData(_ png: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw StoreError.missingImage }
        return try ImageEncoder.pngDataPreservingAlpha(from: NSImage(cgImage: cgImage, size: .zero))
    }

    private func report(_ error: Error) {
        errorMessage = "Couldn't update the screenshot shelf. \(error.localizedDescription)"
    }

    private enum StoreError: LocalizedError {
        case tooLarge
        case missingImage

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "This screenshot exceeds the shelf's storage limit."
            case .missingImage: return "The cached screenshot couldn't be read."
            }
        }
    }
}
