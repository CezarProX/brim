import SwiftUI

/// The Clock widget. Small: weekday, the time large, the date. Medium: the greeting, time and date
/// on the left with the next meeting underneath, and an analog face on the right.
@MainActor
struct HomeClockWidget: View {
  @ObservedObject var calendar: CalendarActivityModel
  var size: HomeWidgetSize
  /// Test hook: pins the clock.
  var fixedDate: Date?

  var body: some View {
    TimelineView(.everyMinute) { context in
      let now = fixedDate ?? context.date
      if size == .small { small(now) } else { medium(now) }
    }
  }

  private func small(_ now: Date) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(now, format: .dateTime.weekday(.wide)).font(IslandFont.label.weight(.semibold))
        .foregroundStyle(IslandTint.timer).textCase(.uppercase).lineLimit(1)
      Spacer(minLength: 0)
      time(now, size: 36)
      Text(now, format: .dateTime.month(.wide).day())
        .font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func medium(_ now: Date) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(IslandClock.greeting(at: now)).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        time(now, size: 34)
        Text(now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
          .font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
        Spacer(minLength: 4)
        if let meeting = calendar.meeting {
          HStack(spacing: 6) {
            Capsule().fill(IslandTint.color(for: .calendar)).frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 0) {
              Text(meeting.title).font(IslandFont.label.weight(.semibold)).lineLimit(1)
              Text(IslandClock.relative(meeting.startsAt, now: now))
                .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
            }
          }
        } else {
          Text("No more events today").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HomeAnalogClock(date: now).frame(width: 96, height: 96)
    }
  }

  private func time(_ now: Date, size: CGFloat) -> some View {
    Text(now, format: .dateTime.hour().minute())
      .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
      .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
  }
}

/// A quiet analog face in the island's ink: hour ticks, hour and minute hands, an orange centre.
struct HomeAnalogClock: View {
  let date: Date
  var calendar: Calendar = .current

  var body: some View {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let minute = Double(parts.minute ?? 0)
    let hour = Double((parts.hour ?? 0) % 12) + minute / 60
    ZStack {
      Circle().fill(IslandFill.subtle)
      Circle().strokeBorder(IslandFill.hairline, lineWidth: 0.75)
      ForEach(0..<12, id: \.self) { tick in
        Capsule().fill(tick % 3 == 0 ? IslandInk.secondary : IslandInk.tertiary)
          .frame(width: tick % 3 == 0 ? 2 : 1.2, height: tick % 3 == 0 ? 8 : 5)
          .offset(y: -38)
          .rotationEffect(.degrees(Double(tick) * 30))
      }
      hand(length: 24, width: 3.5, degrees: hour * 30)
      hand(length: 34, width: 2.5, degrees: minute * 6)
      Circle().fill(IslandTint.timer).frame(width: 6, height: 6)
    }
    .accessibilityHidden(true)
  }

  private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
    Capsule().fill(IslandInk.primary).frame(width: width, height: length)
      .offset(y: -length / 2)
      .rotationEffect(.degrees(degrees))
  }
}
