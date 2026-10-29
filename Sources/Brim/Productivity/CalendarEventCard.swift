import AppKit
import SwiftUI

/// "Event Details": title, time, calendar, location, notes, Join, Count down to this.
struct CalendarEventCard: View {
  let item: CalendarAgendaItem
  let pinned: Bool
  let now: Date
  let toggleCountdown: () -> Void
  let openInCalendar: () -> Void
  let join: (URL) -> Void
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        Text("Event Details").font(IslandFont.label).foregroundStyle(IslandInk.secondary)
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandInk.secondary)
            .frame(width: 28, height: 28).background(IslandFill.raised, in: Circle()).contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle()).accessibilityLabel("Close details")
      }
      Text(item.title).font(IslandFont.headline).lineLimit(2).foregroundStyle(IslandInk.primary)
      line("clock", timeText, tint: IslandInk.secondary)
      if let calendar = item.calendarName { dotLine(calendar) }
      if let location = item.location { line("mappin.and.ellipse", location, tint: IslandInk.tertiary) }
      if let notes = item.notes {
        Text(notes).font(.system(size: 12)).foregroundStyle(IslandInk.tertiary).lineLimit(2)
      }
      if item.start > now, !item.isAllDay || item.start > now {
        Text(CountdownPolicy.phrase(until: item.start, now: now)).font(IslandFont.label.monospacedDigit())
          .foregroundStyle(item.color)
      }
      HStack(spacing: 6) {
        if let url = item.joinURL {
          Button { join(url) } label: { Label("Join", systemImage: "video.fill") }
            .buttonStyle(IslandPillStyle(prominent: true, tint: .green, compact: true))
        }
        Button(action: toggleCountdown) {
          Text(pinned ? "Stop counting down" : "Count down to this").frame(maxWidth: .infinity)
        }
        .buttonStyle(IslandPillStyle(compact: true))
        Button(action: openInCalendar) { Image(systemName: "arrow.up.forward.app") }
          .buttonStyle(IslandPillStyle(compact: true)).help("Open in Calendar")
          .accessibilityLabel("Open in Calendar")
      }
      .padding(.top, 2)
    }
    .padding(IslandSpace.m)
    .frame(width: 260, alignment: .leading)
    .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous).strokeBorder(IslandFill.hairline))
    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
  }

  private func line(_ symbol: String, _ text: String, tint: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: symbol).font(.system(size: 11)).frame(width: 14).foregroundStyle(tint)
      Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).lineLimit(2)
    }
  }

  private func dotLine(_ text: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(item.color).frame(width: 8, height: 8).frame(width: 14)
      Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.tertiary)
    }
  }

  /// "Wed, Oct 14, 2026, 1:00 – 2:00 PM" / "Wed, Oct 14, 2026 · All day".
  var timeText: String {
    let day = item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    if item.isAllDay { return item.spanLabel.map { "\(day) · \($0)" } ?? "\(day) · All day" }
    let start = item.start.formatted(.dateTime.hour().minute())
    guard let end = item.end else { return "\(day), \(start)" }
    return "\(day), \(start) – \(end.formatted(.dateTime.hour().minute()))"
  }
}
