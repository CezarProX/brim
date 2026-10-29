import Foundation

/// Completed focus sessions per day, and the "momentum" streak of consecutive days.
struct FocusSessionLog: Codable, Equatable {
  /// yyyy-MM-dd (in the user's calendar) -> sessions.
  private(set) var days: [String: Int] = [:]

  private static func key(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  func recording(at date: Date, calendar: Calendar = .current) -> FocusSessionLog {
    var next = self
    next.days[Self.key(date, calendar), default: 0] += 1
    // Keep roughly two years; older days can't affect a streak that is still alive.
    if next.days.count > 800 { next.days = Dictionary(uniqueKeysWithValues: next.days.sorted { $0.key > $1.key }.prefix(730).map { ($0.key, $0.value) }) }
    return next
  }

  func sessions(on date: Date, calendar: Calendar = .current) -> Int {
    days[Self.key(date, calendar)] ?? 0
  }

  /// Days in a row with at least one session. Today not having one yet doesn't break
  /// a streak that reaches yesterday; it breaks once a whole day is missed.
  func streak(today: Date, calendar: Calendar = .current) -> Int {
    var cursor = calendar.startOfDay(for: today)
    if sessions(on: cursor, calendar: calendar) == 0 {
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
      cursor = yesterday
    }
    var count = 0
    while sessions(on: cursor, calendar: calendar) > 0, count < 3650 {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previous
    }
    return count
  }
}

/// Persists the log in UserDefaults.
@MainActor
final class FocusSessionStore: ObservableObject {
  static let shared = FocusSessionStore()
  @Published private(set) var log = FocusSessionLog()
  private let defaults: UserDefaults
  private let key = "productivity.pomodoro.sessionLog"

  init(defaults: UserDefaults = AppSettings.shared.defaults) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key), data.count < 200_000,
      let decoded = try? JSONDecoder().decode(FocusSessionLog.self, from: data)
    { log = decoded }
  }

  func recordSession(at date: Date = .now) {
    log = log.recording(at: date)
    if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: key) }
  }

  func streak(today: Date = .now) -> Int { log.streak(today: today) }
  func sessionsToday(now: Date = .now) -> Int { log.sessions(on: now) }
}
