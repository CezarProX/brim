import EventKit
import Foundation
import SwiftUI

enum PinnedCountdownStore {
  private static let key = "productivity.calendar.pinnedCountdown"

  static func load() -> PinnedCountdown? {
    guard let data = AppSettings.shared.defaults.data(forKey: key), data.count < 10_000,
      let pin = try? JSONDecoder().decode(PinnedCountdown.self, from: data),
      CountdownPolicy.isVisible(pin, now: .now)
    else { return nil }
    return pin
  }

  static func save(_ pin: PinnedCountdown?) {
    let defaults = AppSettings.shared.defaults
    if let pin, let data = try? JSONEncoder().encode(pin) { defaults.set(data, forKey: key) }
    else { defaults.removeObject(forKey: key) }
  }
}

extension CalendarActivityModel {
  /// The calendar honoring the week-start setting.
  var weekCalendar: Calendar { CalendarWeekMath.calendar(weekStart: AppSettings.shared.calendarWeekStart) }

  // MARK: Pinned countdown

  /// Pins an event so the compact island counts down to it.
  func countdown(to item: CalendarAgendaItem) {
    guard item.kind == .event else { return }
    let id = item.id.components(separatedBy: "#").first ?? item.id
    let pin = PinnedCountdown(
      eventID: id, title: item.title, start: item.start, end: item.end ?? item.start.addingTimeInterval(3600))
    pinned = pin
    PinnedCountdownStore.save(pin)
    refresh()
  }

  func clearCountdown() {
    pinned = nil
    PinnedCountdownStore.save(nil)
    refresh()
  }

  func isPinned(_ item: CalendarAgendaItem) -> Bool {
    pinned?.eventID == (item.id.components(separatedBy: "#").first ?? item.id)
  }

  /// Replaces `meeting` with the pinned event, or forgets the pin once it has passed.
  func applyPinned(now: Date) {
    guard let pin = pinned else { return }
    guard CountdownPolicy.isVisible(pin, now: now) else {
      pinned = nil
      PinnedCountdownStore.save(nil)
      return
    }
    let match = agendaEvents.first { $0.id == pin.eventID }
    setMeeting(
      CalendarMeeting(
        id: pin.eventID, title: pin.title, startsAt: pin.start, endsAt: pin.end,
        calendar: match?.calendarName ?? "Calendar", joinURL: match?.joinURL))
  }

  // MARK: Destinations and quick add

  /// Calendars that accept events and Reminders lists, for the "@" menu.
  func quickAddDestinations() -> [QuickAddDestination] {
    var result: [QuickAddDestination] = []
    if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
      result += eventStore.calendars(for: .reminder).map {
        QuickAddDestination(id: $0.calendarIdentifier, name: $0.title, kind: .reminderList)
      }
    }
    if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
      result += eventStore.calendars(for: .event).filter(\.allowsContentModifications).map {
        QuickAddDestination(id: $0.calendarIdentifier, name: $0.title, kind: .calendar)
      }
    }
    return result
  }

  /// Saves an interpreted quick-add entry. Returns false and sets `status` on failure.
  @discardableResult
  func save(_ plan: QuickAddPlan) -> Bool {
    do {
      switch plan.output {
      case .event(let draft):
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
          status = "Calendar access is required."
          return false
        }
        let calendar = plan.destination.flatMap { eventStore.calendar(withIdentifier: $0.id) }
          ?? eventStore.defaultCalendarForNewEvents
        guard let calendar else { status = "No calendar can accept new events."; return false }
        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        status = "Added “\(draft.title)” to \(calendar.title)"
      case .reminder(let title, let due, let hasTime):
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
          status = "Reminders access is required."
          return false
        }
        let list = plan.destination.flatMap { eventStore.calendar(withIdentifier: $0.id) }
          ?? eventStore.defaultCalendarForNewReminders()
        guard let list else { status = "No Reminders list is available."; return false }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = list
        if let due {
          let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
          reminder.dueDateComponents = weekCalendar.dateComponents(units, from: due)
        }
        try eventStore.save(reminder, commit: true)
        status = "Added “\(title)” to \(list.title)"
      }
      if let name = plan.destination?.name { AppSettings.shared.quickAddLastDestination = name }
      refresh()
      return true
    } catch {
      status = "Couldn’t save: \(error.localizedDescription)"
      return false
    }
  }
}
