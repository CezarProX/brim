import Foundation

/// How long a file reference may sit in the notch tray before it is dropped.
/// Pinned items are exempt.
enum FileTrayRetention: String, CaseIterable, Identifiable {
  case never = "Never", fiveMinutes = "5 minutes", thirtyMinutes = "30 minutes", hour = "1 hour",
    sixHours = "6 hours", day = "1 day", week = "1 week", month = "1 month"
  var id: String { rawValue }

  var interval: TimeInterval? {
    switch self {
    case .never: nil
    case .fiveMinutes: 300
    case .thirtyMinutes: 1_800
    case .hour: 3_600
    case .sixHours: 21_600
    case .day: 86_400
    case .week: 604_800
    case .month: 2_592_000
    }
  }

  /// Items still within the retention window, plus every pinned item. Files themselves are never touched.
  static func kept(_ items: [FileTrayItem], retention: FileTrayRetention, now: Date = .now) -> [FileTrayItem] {
    guard let interval = retention.interval else { return items }
    return items.filter { $0.pinned || now.timeIntervalSince($0.addedAt) < interval }
  }
}
