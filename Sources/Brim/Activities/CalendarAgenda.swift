import AppKit
import EventKit
import SwiftUI

/// One row of the agenda: a timed or all-day event, or a reminder with a due date.
struct CalendarAgendaItem: Identifiable, Equatable {
  enum Kind: Equatable { case event, reminder }
  let id: String
  let kind: Kind
  let title: String
  let start: Date
  let end: Date?
  let isAllDay: Bool
  let color: Color
  let joinURL: URL?
  var isCompleted = false
  /// "Day 2/3" on each day of a multi-day event.
  var spanLabel: String? = nil
  var location: String? = nil
  var notes: String? = nil
  var calendarName: String? = nil
  var calendarID: String? = nil
}

/// A day heading with its items, in chronological order.
struct CalendarAgendaDay: Identifiable, Equatable {
  let day: Date
  let items: [CalendarAgendaItem]
  var id: Date { day }
}

enum CalendarAgendaBuilder {
  /// Groups items by start day, sorted, dropping days with nothing on them.
  static func group(_ items: [CalendarAgendaItem], calendar: Calendar = .current)
    -> [CalendarAgendaDay]
  {
    let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.start) }
    return grouped.keys.sorted().map { day in
      let sorted = grouped[day, default: []].sorted { lhs, rhs in
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        return lhs.start < rhs.start
      }
      return CalendarAgendaDay(day: day, items: sorted)
    }
  }

  /// The 6×7 grid of dates shown for a month, starting on the locale's first weekday.
  static func monthGrid(for month: Date, calendar: Calendar = .current) -> [Date] {
    guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
    let first = interval.start
    let weekday = calendar.component(.weekday, from: first)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
  }
}

/// Parses quick-add text such as "Lunch with Ana tomorrow at 1pm" entirely on device.
enum CalendarQuickAdd {
  struct Draft: Equatable {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
  }

  static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Draft? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 500,
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    else { return nil }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard let match = detector.firstMatch(in: trimmed, options: [], range: range),
      let date = match.date, let matchRange = Range(match.range, in: trimmed)
    else { return nil }
    var title = trimmed
    title.removeSubrange(matchRange)
    title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    if title.isEmpty { title = "New event" }
    // A detected date without a time of day becomes an all-day event.
    let matched = String(trimmed[matchRange]).lowercased()
    let hasTime =
      matched.range(of: #"\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2}|noon|midnight|\bat\b"#,
        options: .regularExpression) != nil
    if !hasTime {
      let day = calendar.startOfDay(for: date)
      let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
      return Draft(title: title, start: day, end: next, isAllDay: true)
    }
    let duration = match.duration > 0 ? match.duration : 3600
    return Draft(title: title, start: date, end: date.addingTimeInterval(duration), isAllDay: false)
  }
}

extension CalendarActivityModel {
  /// Loads events and due reminders for the next two weeks into `agenda`.
  func refreshAgenda(now: Date = .now) {
    guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      agenda = []
      return
    }
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start.addingTimeInterval(14 * 86_400)
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = eventStore.events(matching: predicate)
      .filter { $0.status != .canceled && ($0.endDate ?? $0.startDate) > now.addingTimeInterval(-3600) }
      .prefix(80)
      .map { event in
        CalendarAgendaItem(
          id: event.eventIdentifier ?? event.calendarItemIdentifier, kind: .event,
          title: String((event.title ?? "Event").prefix(200)), start: event.startDate,
          end: event.endDate, isAllDay: event.isAllDay,
          color: Color(nsColor: event.calendar.color ?? .systemRed),
          joinURL: MeetingLink.find(
            in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
              .joined(separator: "\n")),
          location: event.location.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) },
          notes: event.notes.flatMap { $0.isEmpty ? nil : String($0.prefix(1000)) },
          calendarName: event.calendar.title, calendarID: event.calendar.calendarIdentifier)
      }
    agendaEvents = Array(events)
    publishAgenda()
    guard remindersEnabled, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
      agendaReminders = []
      publishAgenda()
      return
    }
    let reminderPredicate = eventStore.predicateForIncompleteReminders(
      withDueDateStarting: nil, ending: end, calendars: nil)
    eventStore.fetchReminders(matching: reminderPredicate) { [weak self] reminders in
      let items = (reminders ?? []).prefix(60).compactMap { reminder -> CalendarAgendaItem? in
        guard let due = reminder.dueDateComponents.flatMap({ calendar.date(from: $0) }) else {
          return nil
        }
        return CalendarAgendaItem(
          id: reminder.calendarItemIdentifier, kind: .reminder,
          title: String((reminder.title ?? "Reminder").prefix(200)), start: max(due, start),
          end: nil, isAllDay: reminder.dueDateComponents?.hour == nil,
          color: Color(nsColor: reminder.calendar.color ?? .systemOrange), joinURL: nil)
      }
      Task { @MainActor in
        self?.agendaReminders = items
        self?.publishAgenda()
      }
    }
  }

  private func publishAgenda() {
    let today = weekCalendar.startOfDay(for: .now)
    agenda = CalendarAgendaBuilder.groupExpanded(agendaEvents + agendaReminders, calendar: weekCalendar)
      .filter { $0.day >= today }
  }

  func connectReminders() async {
    do {
      guard try await eventStore.requestFullAccessToReminders() else {
        status = "Reminders access is off. Enable Brim in System Settings → Privacy & Security → Reminders."
        return
      }
      AppSettings.shared.remindersActivityEnabled = true
      objectWillChange.send()
      refreshAgenda()
    } catch { status = "Couldn’t connect Reminders: \(error.localizedDescription)" }
  }

  var remindersEnabled: Bool { AppSettings.shared.remindersActivityEnabled }

  /// Marks a reminder done, then removes it from the agenda once saved.
  func complete(reminderID: String) {
    guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
      return
    }
    reminder.isCompleted = true
    do {
      try eventStore.save(reminder, commit: true)
      agendaReminders.removeAll { $0.id == reminderID }
      publishAgenda()
    } catch { status = "Couldn’t complete the reminder: \(error.localizedDescription)" }
  }

  /// Creates an event from quick-add text in the default calendar.
  @discardableResult
  func quickAdd(_ text: String) -> Bool {
    guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
      let draft = CalendarQuickAdd.parse(text),
      let target = eventStore.defaultCalendarForNewEvents
    else {
      status = "Try something like “Lunch tomorrow at 1pm”."
      return false
    }
    let event = EKEvent(eventStore: eventStore)
    event.title = draft.title
    event.startDate = draft.start
    event.endDate = draft.end
    event.isAllDay = draft.isAllDay
    event.calendar = target
    do {
      try eventStore.save(event, span: .thisEvent, commit: true)
      status = "Added “\(draft.title)”"
      refresh()
      return true
    } catch {
      status = "Couldn’t add the event: \(error.localizedDescription)"
      return false
    }
  }
}

/// What the iOS Calendar "Up Next" widget would show: the rest of today, or the next day that has events.
struct CalendarUpNext: Equatable {
  enum Heading: Equatable { case tomorrow, day(Date) }

  /// nil while the events are today's.
  let heading: Heading?
  let events: [CalendarAgendaItem]
  let allDay: [CalendarAgendaItem]
  /// Timed events still ahead or in progress today, including ones not shown.
  let remainingToday: Int

  static let visibleCount = 3

  static func make(_ items: [CalendarAgendaItem], now: Date, calendar: Calendar = .current) -> CalendarUpNext {
    let events = items.filter { $0.kind == .event }
    let today = events.filter { calendar.isDate($0.start, inSameDayAs: now) }
    let allDay = today.filter(\.isAllDay)
    let remaining = today.filter { !$0.isAllDay && ($0.end ?? $0.start) > now }.sorted { $0.start < $1.start }
    if !remaining.isEmpty {
      return CalendarUpNext(heading: nil, events: Array(remaining.prefix(visibleCount)), allDay: allDay,
                            remainingToday: remaining.count)
    }
    let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let later = events.filter { !$0.isAllDay && $0.start >= startOfTomorrow }.sorted { $0.start < $1.start }
    guard let first = later.first else {
      return CalendarUpNext(heading: nil, events: [], allDay: allDay, remainingToday: 0)
    }
    let day = calendar.startOfDay(for: first.start)
    let heading: Heading = calendar.isDate(day, inSameDayAs: startOfTomorrow) ? .tomorrow : .day(day)
    let sameDay = later.filter { calendar.isDate($0.start, inSameDayAs: day) }
    return CalendarUpNext(heading: heading, events: Array(sameDay.prefix(2)), allDay: allDay, remainingToday: 0)
  }

  /// How far through an event `now` is, 0...1.
  static func progress(of item: CalendarAgendaItem, now: Date) -> Double {
    guard let end = item.end, end > item.start else { return 0 }
    return min(1, max(0, now.timeIntervalSince(item.start) / end.timeIntervalSince(item.start)))
  }

  /// "Now", "in 12 min", "in 2 hr 30 min".
  static func countdown(to item: CalendarAgendaItem, now: Date) -> String {
    let minutes = Int((item.start.timeIntervalSince(now) / 60).rounded(.up))
    guard minutes > 0 else { return "Now" }
    return "in " + BatteryStatus.duration(minutes)
  }
}
