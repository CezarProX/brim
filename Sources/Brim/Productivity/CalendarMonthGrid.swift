import SwiftUI

/// The month grid: weekday header, optional ISO week numbers, today in red, busy-day dots.
struct CalendarMonthGrid: View {
  let month: Date
  let calendar: Calendar
  var today: Date = .now
  let showWeekNumbers: Bool
  let selectedDay: Date?
  let busyDays: Set<Date>
  let onSelect: (Date) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let red = IslandTint.color(for: .calendar)

  var body: some View {
    let weeks = CalendarWeekMath.weeks(of: CalendarAgendaBuilder.monthGrid(for: month, calendar: calendar))
    VStack(spacing: 1) {
      HStack(spacing: 0) {
        if showWeekNumbers { Color.clear.frame(width: 22, height: 1) }
        ForEach(Array(CalendarWeekMath.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { index, symbol in
          Text(symbol).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isWeekend(index) ? IslandInk.tertiary.opacity(0.7) : IslandInk.tertiary)
            .frame(maxWidth: .infinity)
        }
      }
      ForEach(weeks, id: \.first) { week in
        HStack(spacing: 0) {
          if showWeekNumbers {
            Text("\(CalendarWeekMath.weekNumber(of: week[0], calendar: calendar))")
              .font(.system(size: 11, weight: .medium)).monospacedDigit()
              .foregroundStyle(IslandInk.tertiary.opacity(0.8)).frame(width: 22)
          }
          ForEach(week, id: \.self) { day in cell(day) }
        }
      }
    }
  }

  private func isWeekend(_ column: Int) -> Bool {
    let weekday = (calendar.firstWeekday - 1 + column) % 7 + 1
    return weekday == 1 || weekday == 7
  }

  private func cell(_ day: Date) -> some View {
    let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
    let busy = busyDays.contains(calendar.startOfDay(for: day))
    return Button { onSelect(day) } label: {
      Text("\(calendar.component(.day, from: day))")
        .font(.system(size: 13, weight: isToday || selected ? .bold : .medium)).monospacedDigit()
        .foregroundStyle(
          isToday ? Color.white : selected ? Color.black : inMonth ? IslandInk.primary : IslandInk.tertiary.opacity(0.5)
        )
        .frame(width: 26, height: 26)
        .background {
          if isToday { Circle().fill(red) } else if selected { Circle().fill(Color.white) }
        }
        .overlay(alignment: .bottom) {
          if busy && !isToday && !selected {
            Circle().fill(IslandInk.secondary).frame(width: 3, height: 3).offset(y: 1)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.85))
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
