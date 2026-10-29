import Foundation
import SwiftUI
import Testing

@testable import Brim

struct CalendarUpNextTests {
  private let calendar = Calendar(identifier: .gregorian)
  private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 0))! }

  private func event(_ id: String, _ startHour: Double, _ endHour: Double, day: Int = 0, allDay: Bool = false,
                     kind: CalendarAgendaItem.Kind = .event) -> CalendarAgendaItem {
    let base = calendar.startOfDay(for: now).addingTimeInterval(Double(day) * 86_400)
    return CalendarAgendaItem(id: id, kind: kind, title: id, start: base.addingTimeInterval(startHour * 3600),
                              end: base.addingTimeInterval(endHour * 3600), isAllDay: allDay, color: .red, joinURL: nil)
  }

  @Test func showsWhatIsOnNowThenTheRestOfToday() {
    let items = [event("done", 9, 10), event("now", 13.5, 14.5), event("later", 16, 17), event("evening", 19, 20),
                 event("night", 21, 22), event("holiday", 0, 24, allDay: true), event("buy milk", 15, 15, kind: .reminder)]
    let upNext = CalendarUpNext.make(items, now: now, calendar: calendar)
    #expect(upNext.heading == nil)
    #expect(upNext.events.map(\.id) == ["now", "later", "evening"])
    #expect(upNext.allDay.map(\.id) == ["holiday"])
    #expect(upNext.remainingToday == 4)
  }

  @Test func emptyEveningLooksAheadToTheNextDayWithEvents() {
    let items = [event("done", 9, 10), event("standup", 9, 9.25, day: 1), event("review", 11, 12, day: 1),
                 event("far", 10, 11, day: 3)]
    let upNext = CalendarUpNext.make(items, now: now, calendar: calendar)
    #expect(upNext.heading == .tomorrow)
    #expect(upNext.events.map(\.id) == ["standup", "review"])
  }

  @Test func laterDayIsNamed() {
    let upNext = CalendarUpNext.make([event("far", 10, 11, day: 3)], now: now, calendar: calendar)
    if case .day(let date) = upNext.heading {
      #expect(calendar.isDate(date, inSameDayAs: now.addingTimeInterval(3 * 86_400)))
    } else {
      Issue.record("expected a named day, got \(String(describing: upNext.heading))")
    }
  }

  @Test func nothingScheduledIsEmpty() {
    let upNext = CalendarUpNext.make([event("done", 9, 10)], now: now, calendar: calendar)
    #expect(upNext.events.isEmpty)
    #expect(upNext.heading == nil)
  }

  @Test func progressAndCountdownDescribeTheFirstEvent() {
    let running = event("now", 13.5, 14.5)
    #expect(CalendarUpNext.progress(of: running, now: now) == 0.5)
    #expect(CalendarUpNext.countdown(to: event("soon", 14.2, 15), now: now) == "in 12 min")
    #expect(CalendarUpNext.countdown(to: event("later", 16.5, 17), now: now) == "in 2 hr 30 min")
    #expect(CalendarUpNext.countdown(to: running, now: now) == "Now")
  }
}
