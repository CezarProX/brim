import AppKit

/// Entry point for opening the Cleaner. It lives in the island's Widgets tab; Settings and other
/// callers ask the island to open it.
@MainActor
final class CleanerController {
  static let shared = CleanerController()

  /// Which list the island should open on. Read once by the view's model.
  private(set) var pendingMode: CleanerModel.Mode = .uninstall

  func show(mode: CleanerModel.Mode = .uninstall) {
    pendingMode = mode
    NotchShelfController.shared.presentWidget(.cleaner)
  }

  func consumePendingMode() -> CleanerModel.Mode {
    defer { pendingMode = .uninstall }
    return pendingMode
  }
}
