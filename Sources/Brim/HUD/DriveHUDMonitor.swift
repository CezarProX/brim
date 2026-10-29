import AppKit
import SwiftUI

/// Which mounted volumes deserve a "Drive connected" HUD: external, local, browsable disks,
/// not the boot volume, network shares, disk images or hidden system volumes.
enum DriveHUDRules {
  struct Volume: Equatable {
    var isInternal: Bool?
    var isLocal: Bool
    var isBrowsable: Bool
    var isEjectable: Bool
    var isRemovable: Bool
    var path: String
  }

  static func shouldAnnounce(_ volume: Volume) -> Bool {
    guard volume.isLocal, volume.isBrowsable, volume.path != "/", !volume.path.hasPrefix("/System/") else {
      return false
    }
    return volume.isEjectable || volume.isRemovable || volume.isInternal == false
  }

  static func sizeText(_ bytes: Int?) -> String? {
    guard let bytes, bytes > 0 else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}

/// Drive connected (with size and an Eject action) and ejected, from NSWorkspace mount events.
@MainActor
final class DriveHUDMonitor {
  static let shared = DriveHUDMonitor()
  private var tokens: [NSObjectProtocol] = []
  private var announced: [String: String] = [:]
  private let flashes = IslandFlashCenter.shared

  func refresh() {
    if AppSettings.shared.hudDrives, tokens.isEmpty {
      let center = NSWorkspace.shared.notificationCenter
      tokens = [
        center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
          let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
          Task { @MainActor in if let url { self?.mounted(url) } }
        },
        center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
          let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
          Task { @MainActor in if let url { self?.unmounted(url) } }
        },
      ]
    } else if !AppSettings.shared.hudDrives {
      let center = NSWorkspace.shared.notificationCenter
      tokens.forEach(center.removeObserver)
      tokens = []
      announced = [:]
    }
  }

  private func mounted(_ url: URL) {
    let keys: Set<URLResourceKey> = [
      .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsEjectableKey,
      .volumeIsRemovableKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]
    guard let values = try? url.resourceValues(forKeys: keys) else { return }
    let volume = DriveHUDRules.Volume(
      isInternal: values.volumeIsInternal, isLocal: values.volumeIsLocal ?? false,
      isBrowsable: values.volumeIsBrowsable ?? false, isEjectable: values.volumeIsEjectable ?? false,
      isRemovable: values.volumeIsRemovable ?? false, path: url.path)
    guard DriveHUDRules.shouldAnnounce(volume) else { return }
    let name = values.volumeName ?? url.lastPathComponent
    announced[url.path] = name
    flashes.show(
      name, symbol: "externaldrive.fill", tint: .white, duration: 6, kind: .drive,
      detail: DriveCapacity.text(
        available: values.volumeAvailableCapacityForImportantUsage.map { Int($0) }, total: values.volumeTotalCapacity)
        ?? "Drive connected",
      action: HUDAction(title: "Eject", symbol: "eject.fill") { [weak self] in self?.eject(url, name: name) },
      shortTitle: "Drive")
  }

  private func unmounted(_ url: URL) {
    guard let name = announced.removeValue(forKey: url.path) else { return }
    flashes.show(
      name, symbol: "checkmark.circle.fill", tint: .green, duration: 2.6, kind: .drive,
      detail: "Ejected · safe to remove", shortTitle: "Ejected")
  }

  private func eject(_ url: URL, name: String) {
    Task.detached(priority: .userInitiated) {
      let failure: Error?
      do {
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        failure = nil
      } catch {
        failure = error
      }
      await MainActor.run {
        guard failure != nil else { return }
        IslandFlashCenter.shared.show(
          "Couldn’t eject", symbol: "exclamationmark.triangle.fill", tint: .red, duration: 3.5, kind: .drive,
          detail: "\(name) is in use", shortTitle: "Eject failed")
      }
    }
  }
}
