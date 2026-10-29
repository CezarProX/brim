import Foundation

/// Week-start and week-number rules shared by the month grid and agenda headings.
enum CalendarWeekMath {
  /// A calendar whose first weekday follows the setting (0 = system).
  static func calendar(weekStart: Int, base: Calendar = .current) -> Calendar {
    var copy = base
    if (1...7).contains(weekStart) { copy.firstWeekday = weekStart }
    return copy
  }

  /// Very short weekday symbols in grid order.
  static func weekdaySymbols(calendar: Calendar) -> [String] {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let first = calendar.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first])
  }

  /// ISO-8601 week number of a date, 1...53.
  static func weekNumber(of date: Date, calendar: Calendar = .current) -> Int {
    var iso = Calendar(identifier: .iso8601)
    iso.timeZone = calendar.timeZone
    return iso.component(.weekOfYear, from: date)
  }

  /// The 6 rows of the month grid, each a week of 7 dates.
  static func weeks(of grid: [Date]) -> [[Date]] {
    stride(from: 0, to: grid.count, by: 7).map { Array(grid[$0..<min($0 + 7, grid.count)]) }
  }
}

extension CalendarAgendaBuilder {
  /// Like `group`, but multi-day events appear on every day they cover and all-day
  /// events end on their last day (EventKit stores the end as the next midnight).
  static func groupExpanded(_ items: [CalendarAgendaItem], calendar: Calendar = .current)
    -> [CalendarAgendaDay]
  {
    var expanded: [CalendarAgendaItem] = []
    for item in items {
      guard item.kind == .event, let end = item.end else {
        expanded.append(item)
        continue
      }
      let firstDay = calendar.startOfDay(for: item.start)
      let lastInstant = end > item.start ? end.addingTimeInterval(-1) : end
      let lastDay = max(firstDay, calendar.startOfDay(for: lastInstant))
      let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
      guard span > 0, span < 60 else {
        expanded.append(item)
        continue
      }
      for offset in 0...span {
        guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
        expanded.append(
          item.continuation(on: day, dayIndex: offset + 1, of: span + 1))
      }
    }
    return group(expanded, calendar: calendar)
  }
}

extension CalendarAgendaItem {
  /// This event as shown on one day of a multi-day span; later days render as all-day bars.
  func continuation(on day: Date, dayIndex: Int, of total: Int) -> CalendarAgendaItem {
    guard dayIndex > 1 else {
      return CalendarAgendaItem(
        id: id, kind: kind, title: title, start: start, end: end, isAllDay: isAllDay, color: color,
        joinURL: joinURL, isCompleted: isCompleted, spanLabel: "Day 1/\(total)",
        location: location, notes: notes, calendarName: calendarName, calendarID: calendarID)
    }
    return CalendarAgendaItem(
      id: "\(id)#\(dayIndex)", kind: kind, title: title, start: day, end: end, isAllDay: true,
      color: color, joinURL: joinURL, isCompleted: isCompleted, spanLabel: "Day \(dayIndex)/\(total)",
      location: location, notes: notes, calendarName: calendarName, calendarID: calendarID)
  }
}
