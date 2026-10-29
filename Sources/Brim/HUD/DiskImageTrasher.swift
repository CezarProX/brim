import AppKit
import Foundation

/// "Trash disk image after install": when a mounted .dmg from Downloads is ejected, move the .dmg
/// to the Trash. The image path comes from `hdiutil info -plist`, read off the main thread.
enum DiskImageInfo {
    /// Mount point -> image path, from the plist `hdiutil info -plist` prints.
    static func parse(_ data: Data) -> [String: String] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for image in images {
            guard let path = image["image-path"] as? String else { continue }
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                if let mount = entity["mount-point"] as? String { result[mount] = path }
            }
        }
        return result
    }

    /// Only .dmg files inside the Downloads folder are ever trashed.
    static func isTrashable(path: String, downloads: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return DownloadFileRules.isDiskImage(url.lastPathComponent)
            && url.deletingLastPathComponent().path == URL(fileURLWithPath: downloads).standardizedFileURL.path
    }
}

@MainActor
final class DiskImageTrasher {
    static let shared = DiskImageTrasher()
    private var tokens: [NSObjectProtocol] = []
    private var images: [String: String] = [:]

    func refresh() {
        if AppSettings.shared.trashDiskImageAfterInstall, tokens.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            tokens = [
                center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.scan() }
                },
                center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
                    let path = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
                    Task { @MainActor in if let path { self?.unmounted(path) } }
                },
            ]
            scan()
        } else if !AppSettings.shared.trashDiskImageAfterInstall {
            tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            tokens = []
            images = [:]
        }
    }

    private func scan() {
        Task.detached(priority: .utility) {
            let data = BluetoothBatteryProbe.boundedOutput(executable: "/usr/bin/hdiutil", arguments: ["info", "-plist"], timeout: 5)
            let parsed = data.map(DiskImageInfo.parse) ?? [:]
            await MainActor.run { [weak self] in self?.images = parsed }
        }
    }

    private func unmounted(_ mountPoint: String) {
        guard let path = images.removeValue(forKey: mountPoint),
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
              DiskImageInfo.isTrashable(path: path, downloads: downloads) else { return }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            IslandFlashCenter.shared.show(url.lastPathComponent, symbol: "trash.fill", tint: .white, duration: 3,
                                          kind: .drive, detail: "Disk image moved to the Trash", shortTitle: "Trashed")
        } catch {
            IslandFlashCenter.shared.show("Couldn’t trash image", symbol: "exclamationmark.triangle.fill", tint: .red,
                                          duration: 3, kind: .drive, detail: url.lastPathComponent, shortTitle: "Not trashed")
        }
    }
}
