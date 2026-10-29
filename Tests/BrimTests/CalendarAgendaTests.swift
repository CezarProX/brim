import Foundation
import SwiftUI
import Testing

@testable import Brim

struct CalendarAgendaTests {
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Europe/Bucharest")!
    value.firstWeekday = 2
    return value
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  @Test func monthGridStartsOnFirstWeekdayAndHasSixWeeks() {
    let grid = CalendarAgendaBuilder.monthGrid(for: date(2026, 9, 15), calendar: calendar)
    #expect(grid.count == 42)
    // September 2026 starts on a Tuesday, so a Monday-first grid opens on August 31.
    #expect(calendar.isDate(grid[0], inSameDayAs: date(2026, 8, 31)))
    #expect(calendar.isDate(grid[1], inSameDayAs: date(2026, 9, 1)))
  }

  @Test func groupsByDayWithAllDayItemsFirst() {
    let items = [
      CalendarAgendaItem(
        id: "b", kind: .event, title: "Late", start: date(2026, 9, 24, 15), end: nil,
        isAllDay: false, color: .red, joinURL: nil),
      CalendarAgendaItem(
        id: "c", kind: .event, title: "Tomorrow", start: date(2026, 9, 25, 9), end: nil,
        isAllDay: false, color: .red, joinURL: nil),
      CalendarAgendaItem(
        id: "a", kind: .reminder, title: "All day", start: date(2026, 9, 24), end: nil,
        isAllDay: true, color: .orange, joinURL: nil),
    ]
    let days = CalendarAgendaBuilder.group(items, calendar: calendar)
    #expect(days.count == 2)
    #expect(days[0].items.map(\.id) == ["a", "b"])
    #expect(days[1].items.map(\.id) == ["c"])
  }

  @Test func quickAddParsesTitleAndTime() throws {
    let now = date(2026, 9, 24, 10)
    let draft = try #require(CalendarQuickAdd.parse("Lunch with Ana tomorrow at 1pm", now: now))
    #expect(draft.title == "Lunch with Ana")
    #expect(!draft.isAllDay)
    #expect(draft.end.timeIntervalSince(draft.start) == 3600)
  }

  @Test func quickAddWithoutTimeBecomesAllDay() throws {
    let draft = try #require(CalendarQuickAdd.parse("Mom's birthday on October 3", calendar: calendar))
    #expect(draft.isAllDay)
    #expect(draft.title.localizedCaseInsensitiveContains("birthday"))
    #expect(draft.end.timeIntervalSince(draft.start) == 86_400)
  }

  @Test func quickAddRejectsTextWithoutADate() {
    #expect(CalendarQuickAdd.parse("buy milk") == nil)
    #expect(CalendarQuickAdd.parse("   ") == nil)
  }
}
