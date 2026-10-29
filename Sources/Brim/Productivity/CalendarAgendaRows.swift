import SwiftUI

/// Event or reminder row, tinted with its calendar's color.
struct AgendaRow: View {
  let item: CalendarAgendaItem
  let open: () -> Void
  let join: (URL) -> Void
  let complete: () -> Void
  var pinned = false
  @State private var hovered = false
  @State private var checking = false

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      if item.kind == .reminder { checkbox } else {
        Capsule().fill(item.color).frame(width: 3)
      }
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            .foregroundStyle(item.kind == .event ? item.color : IslandInk.primary)
          if pinned {
            Image(systemName: "timer").font(.system(size: 10, weight: .bold)).foregroundStyle(item.color)
          }
        }
        if let subtitle { Text(subtitle).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
          .foregroundStyle(item.kind == .event ? item.color.opacity(0.85) : IslandInk.tertiary) }
      }
      Spacer(minLength: 0)
      if let url = item.joinURL, item.kind == .event {
        // One tap from the agenda straight into the call.
        Button { join(url) } label: { Label("Join", systemImage: "video.fill") }
          .buttonStyle(IslandPillStyle(prominent: true, tint: .green, compact: true))
          .accessibilityLabel("Join \(item.title)")
      }
    }
    .padding(.horizontal, IslandSpace.s).padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    .background(background, in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
    .contentShape(Rectangle())
    .onTapGesture { if item.kind == .event { open() } }
    .onHover { hovered = $0 }
    .accessibilityElement(children: .combine)
    .accessibilityHint(item.kind == .event ? "Shows event details" : "")
  }

  private var background: Color {
    item.kind == .event ? item.color.opacity(item.isAllDay ? 0.34 : hovered ? 0.28 : 0.18) : IslandFill.subtle
  }

  /// "9:30 – 9:45 AM", "All day", or "Day 2/3".
  private var subtitle: String? {
    if let span = item.spanLabel, item.isAllDay { return span }
    if item.isAllDay { return item.kind == .event ? "All day" : nil }
    let start = item.start.formatted(.dateTime.hour().minute())
    guard let end = item.end, item.kind == .event else { return start }
    return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
  }

  private var checkbox: some View {
    Button {
      checking = true
      complete()
    } label: {
      Image(systemName: checking ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 17, weight: .medium)).frame(width: 28, height: 28).contentShape(Rectangle())
        .foregroundStyle(checking ? item.color : Color.blue.opacity(0.9))
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.8))
    .accessibilityLabel("Complete \(item.title)")
  }
}

/// A Things 3 to-do shown in the agenda, with a checkbox that completes it in Things.
struct ThingsRow: View {
  let todo: ThingsTodo
  let complete: () -> Void
  @State private var checking = false

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      Button {
        checking = true
        complete()
      } label: {
        Image(systemName: checking ? "checkmark.circle.fill" : "circle").font(.system(size: 17))
          .frame(width: 28, height: 28).contentShape(Rectangle()).foregroundStyle(Color.blue).contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.8))
      .accessibilityLabel("Complete \(todo.title)")
      VStack(alignment: .leading, spacing: 1) {
        Text(todo.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(IslandInk.primary)
        if let project = todo.project {
          Text(project).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "checklist").font(.system(size: 11)).foregroundStyle(IslandInk.tertiary)
    }
    .padding(.horizontal, IslandSpace.s).padding(.vertical, 4)
    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    .glassCard(radius: IslandRadius.small)
  }
}
