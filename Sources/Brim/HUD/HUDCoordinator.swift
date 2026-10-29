import Foundation

/// One place for the integrator to start and refresh every system HUD source.
@MainActor
enum HUDCoordinator {
  /// Call once at launch, after the island exists.
  static func start() { refresh() }

  /// Call at launch and whenever a HUD setting changes (the settings section does this itself).
  static func refresh() {
    SystemHUDController.shared.refresh()
    NetworkHUDMonitor.shared.refresh()
    DriveHUDMonitor.shared.refresh()
    BluetoothHUDMonitor.shared.refresh()
    FocusHUDMonitor.shared.refresh()
    DownloadProgressModel.shared.refresh()
    DiskImageTrasher.shared.refresh()
  }

  static func stop() {
    SystemHUDController.shared.stop()
  }
}
