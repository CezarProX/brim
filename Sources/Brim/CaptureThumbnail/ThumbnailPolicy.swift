import AppKit

/// When a finished capture gets a floating thumbnail, and on which screen.
enum ThumbnailPolicy {
  /// Every action that hands the capture somewhere shows it, except printing. Return only does so
  /// when it copies (otherwise the capture is still being worked on in the overlay).
  static func presents(_ action: OverlayAction, copyAfterSelection: Bool, enabled: Bool) -> Bool {
    guard enabled else { return false }
    switch action {
    case .copy, .save, .upload, .share: return true
    case .confirm: return copyAfterSelection
    case .print: return false
    }
  }
}

/// A screen the thumbnails can stack on: its display and its visible frame (menu bar and Dock excluded).
struct ThumbnailPlacement: Equatable {
  let displayID: CGDirectDisplayID
  let bounds: CGRect

  /// The screen with `displayID`; when it is gone, the one under the pointer, then the main screen.
  @MainActor
  static func resolve(_ displayID: CGDirectDisplayID?) -> ThumbnailPlacement? {
    let screens = NSScreen.screens
    let screen = screens.first { displayID != nil && $0.thumbnailDisplayID == displayID }
      ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main ?? screens.first
    guard let screen else { return nil }
    return ThumbnailPlacement(displayID: screen.thumbnailDisplayID ?? 0, bounds: screen.visibleFrame)
  }
}

extension NSScreen {
  var thumbnailDisplayID: CGDirectDisplayID? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
}
