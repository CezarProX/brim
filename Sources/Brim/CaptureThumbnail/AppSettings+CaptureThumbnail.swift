import Foundation

/// The screen corner the floating capture thumbnails sit in.
enum ThumbnailCorner: String, CaseIterable, Identifiable {
  case bottomRight, bottomLeft, topRight, topLeft

  var id: String { rawValue }
  var isRight: Bool { self == .bottomRight || self == .topRight }
  var isBottom: Bool { self == .bottomRight || self == .bottomLeft }
  /// +1 when the nearest vertical screen edge is on the right, -1 on the left.
  var outward: CGFloat { isRight ? 1 : -1 }

  var title: String {
    switch self {
    case .bottomRight: L10n.tr("Bottom right")
    case .bottomLeft: L10n.tr("Bottom left")
    case .topRight: L10n.tr("Top right")
    case .topLeft: L10n.tr("Top left")
    }
  }
}

/// Preferences for the floating thumbnail shown after a capture.
extension AppSettings {
  /// The delays the Settings picker offers; 0 keeps a thumbnail until it is closed.
  static let captureThumbnailDelayChoices: [TimeInterval] = [3, 6, 10, 20, 0]

  var captureThumbnailEnabled: Bool {
    get { defaults.object(forKey: "captureThumbnailEnabled") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "captureThumbnailEnabled") }
  }

  var captureThumbnailCorner: ThumbnailCorner {
    get { defaults.string(forKey: "captureThumbnailCorner").flatMap(ThumbnailCorner.init(rawValue:)) ?? .bottomRight }
    set { defaults.set(newValue.rawValue, forKey: "captureThumbnailCorner") }
  }

  /// Seconds before an untouched thumbnail closes by itself; 0 means never. Clamped to 0...60.
  var captureThumbnailAutoClose: TimeInterval {
    get { min(60, max(0, defaults.object(forKey: "captureThumbnailAutoClose") as? Double ?? 6)) }
    set { defaults.set(min(60, max(0, newValue)), forKey: "captureThumbnailAutoClose") }
  }
}
