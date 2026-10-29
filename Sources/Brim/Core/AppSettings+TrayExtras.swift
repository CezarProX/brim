import Foundation

/// Tray placement, protection and automation settings (file tray options).
extension AppSettings {
  private enum TrayKey {
    static let placement = "trayPlacement"
    static let openAfterDrop = "trayOpenAfterDrop"
    static let protectOriginals = "trayProtectOriginals"
    static let removeAfterDragOut = "trayRemoveAfterDragOut"
    static let sync = "floatingTraySync"
    static let trackedEnabled = "trayTrackedFoldersEnabled"
    static let trackedPaths = "trayTrackedFolderPaths"
    static let trackedOCR = "trayTrackedAutoOCR"
    static let mailApp = "trayMailAppBundleID"
  }

  /// Where trays appear. Default: each gesture uses its own surface.
  var trayPlacement: TrayPlacement {
    get { defaults.string(forKey: TrayKey.placement).flatMap(TrayPlacement.init(rawValue:)) ?? .both }
    set { defaults.set(newValue.rawValue, forKey: TrayKey.placement) }
  }

  /// Switch the island to the Tray page after files are dropped on it.
  var trayOpenAfterDrop: Bool {
    get { defaults.object(forKey: TrayKey.openAfterDrop) as? Bool ?? true }
    set { defaults.set(newValue, forKey: TrayKey.openAfterDrop) }
  }

  /// Move/Rename work on copies and drag-out hands over a copy, so originals never change.
  var trayProtectOriginals: Bool {
    get { defaults.object(forKey: TrayKey.protectOriginals) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TrayKey.protectOriginals) }
  }

  var trayRemoveAfterDragOut: Bool {
    get { defaults.object(forKey: TrayKey.removeAfterDragOut) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TrayKey.removeAfterDragOut) }
  }

  /// Every floating tray shows the same files.
  var floatingTraySync: Bool {
    get { defaults.object(forKey: TrayKey.sync) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TrayKey.sync) }
  }

  var trackedFoldersEnabled: Bool {
    get { defaults.object(forKey: TrayKey.trackedEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TrayKey.trackedEnabled) }
  }

  var trackedFolderPaths: [String] {
    get { defaults.stringArray(forKey: TrayKey.trackedPaths) ?? [] }
    set { defaults.set(Array(NSOrderedSet(array: newValue)) as? [String] ?? newValue, forKey: TrayKey.trackedPaths) }
  }

  /// Copy the text out of images that arrive from a tracked folder.
  var trackedFoldersAutoOCR: Bool {
    get { defaults.object(forKey: TrayKey.trackedOCR) as? Bool ?? false }
    set { defaults.set(newValue, forKey: TrayKey.trackedOCR) }
  }

  /// Bundle id of the mail app for the Mail action; empty uses Apple Mail's sharing service.
  var trayMailAppBundleID: String {
    get { defaults.string(forKey: TrayKey.mailApp) ?? "" }
    set { defaults.set(newValue, forKey: TrayKey.mailApp) }
  }
}
