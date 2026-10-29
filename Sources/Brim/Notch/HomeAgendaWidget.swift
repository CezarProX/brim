import SwiftUI

/// The Calendar widget, as Apple's Up Next. Small: weekday and date, then the next event.
/// Medium: the date in a column on the left, the next three events on the right.
@MainActor
struct HomeAgendaWidget: View {
  @ObservedObject var calendar: CalendarActivityModel
  var size: HomeWidgetSize
  let open: () -> Void
  /// Test hook: shows these instead of the calendar's own.
  var fixedItems: [CalendarAgendaItem]?

  private var items: [CalendarAgendaItem] {
    fixedItems ?? calendar.agenda.flatMap(\.items).filter { !$0.isCompleted }
  }

  var body: some View {
    if size == .small { small } else { medium }
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 0) {
      dateHeader(daySize: 30)
      Spacer(minLength: 6)
      if let next = items.first {
        Button(action: open) { row(next, titleLines: 2) }.buttonStyle(IslandPressStyle(pressedScale: 0.97))
      } else {
        emptyState
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var medium: some View {
    HStack(alignment: .top, spacing: 14) {
      dateHeader(daySize: 40).frame(width: 78, alignment: .leading)
      VStack(alignment: .leading, spacing: 7) {
        if items.isEmpty {
          Spacer(minLength: 0)
          emptyState
        } else {
          ForEach(Array(items.prefix(3))) { item in
            Button(action: open) { row(item, titleLines: 1) }.buttonStyle(IslandPressStyle(pressedScale: 0.97))
          }
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func dateHeader(daySize: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: -2) {
      Text(Date.now, format: .dateTime.weekday(.wide)).font(IslandFont.label.weight(.semibold))
        .foregroundStyle(IslandTint.color(for: .calendar)).textCase(.uppercase).lineLimit(1)
      Text(Date.now, format: .dateTime.day())
        .font(.system(size: daySize, weight: .regular, design: .rounded)).monospacedDigit()
    }
  }

  private func row(_ item: CalendarAgendaItem, titleLines: Int) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Capsule().fill(item.color).frame(width: 3).frame(maxHeight: .infinity)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.primary)
          .lineLimit(titleLines).multilineTextAlignment(.leading)
        Group {
          if item.isAllDay { Text("All day") } else { Text(item.start, style: .time) }
        }
        .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(calendar.enabled ? "No tasks or events" : "Connect Calendar")
        .font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary).lineLimit(2)
      Text(calendar.enabled ? "Everything is clear for now." : "See what’s next at a glance.")
        .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(2)
    }
  }
}
