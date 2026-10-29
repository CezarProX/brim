import Foundation

/// One in-progress download found in a folder.
struct DownloadEntry: Equatable {
    let partialName: String
    let bytes: Int64
    let totalBytes: Int64?
    var finalName: String { DownloadFileRules.finalName(forPartial: partialName) }
}

/// Reads the partial files in a folder. Only metadata is touched, never file contents.
enum DownloadScanner {
    static func scan(folder: URL, fileManager: FileManager = .default) -> [DownloadEntry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter(DownloadFileRules.isPartial).compactMap { entry(folder: folder, name: $0, fileManager: fileManager) }
    }

    private static func entry(folder: URL, name: String, fileManager: FileManager) -> DownloadEntry? {
        let url = folder.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else {
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return DownloadEntry(partialName: name, bytes: size, totalBytes: nil)
        }
        // Safari bundle: data file(s) beside Info.plist.
        let children = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        let bytes = children.filter { $0 != "Info.plist" }.reduce(Int64(0)) { sum, child in
            let size = (try? fileManager.attributesOfItem(atPath: url.appendingPathComponent(child).path)[.size] as? NSNumber)?.int64Value
            return sum + (size ?? 0)
        }
        let total = (try? Data(contentsOf: url.appendingPathComponent("Info.plist"))).flatMap(DownloadFileRules.expectedBytes)
        return DownloadEntry(partialName: name, bytes: bytes, totalBytes: total)
    }
}
