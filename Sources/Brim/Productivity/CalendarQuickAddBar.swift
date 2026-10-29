import SwiftUI

/// Natural-language quick add: type "Lunch with Sam tomorrow at 1pm", "@" picks the destination.
struct CalendarQuickAddBar: View {
  @Binding var text: String
  let destinations: [QuickAddDestination]
  let submit: () -> Void
  @FocusState private var focused: Bool
  @State private var highlighted = 0

  private var input: QuickAddInput { QuickAddInput.split(text, known: destinations.map(\.name)) }
  private var menu: [QuickAddDestination]? {
    input.openQuery.map { QuickAddDestinations.menu(matching: $0, in: destinations) }
  }

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      TextField("Lunch with Sam tomorrow at 1pm @Work", text: $text)
        .textFieldStyle(.plain).font(IslandFont.body).focused($focused)
        .onSubmit(commit)
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onChange(of: input.openQuery) { _, _ in highlighted = 0 }
      Image(systemName: "at").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
        .help("Type @ to choose a calendar or Reminders list")
      Button(action: commit) {
        Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24)
          .background(IslandTint.color(for: .calendar), in: Circle())
      }
      .buttonStyle(IslandPressStyle())
      .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
      .accessibilityLabel("Add")
    }
    .padding(.leading, IslandSpace.m).padding(.trailing, 5).frame(height: 32)
    .background(IslandFill.raised, in: Capsule())
    .overlay(alignment: .topLeading) { if let rows = menu, !rows.isEmpty { menuView(rows).offset(y: 36) } }
    .overlay(alignment: .bottomLeading) { preview.offset(x: IslandSpace.m, y: 17) }
    .onAppear { focused = true }
    .zIndex(1)
  }

  private var preview: some View {
    let plan = QuickAddPlan.make(text, destinations: destinations)
    return Group {
      if let plan, menu == nil { Text(describe(plan)).font(IslandFont.label).foregroundStyle(IslandInk.tertiary) }
    }
  }

  private func describe(_ plan: QuickAddPlan) -> String {
    let target = plan.destination?.name
    switch plan.output {
    case .event(let draft):
      let when = draft.isAllDay
        ? draft.start.formatted(date: .abbreviated, time: .omitted)
        : draft.start.formatted(date: .abbreviated, time: .shortened)
      return "\(when) · \(target ?? "default calendar")"
    case .reminder(_, let due, let hasTime):
      let when = due.map { hasTime ? $0.formatted(date: .abbreviated, time: .shortened) : $0.formatted(date: .abbreviated, time: .omitted) }
      return "Reminder · \(target ?? "Reminders")" + (when.map { " · " + $0 } ?? "")
    }
  }

  private func menuView(_ rows: [QuickAddDestination]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
        if index == 0 || rows[index - 1].kind != row.kind {
          Text(row.kind == .reminderList ? "Reminder list" : "Calendar")
            .font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
            .padding(.horizontal, 10).padding(.top, index == 0 ? 6 : 8).padding(.bottom, 3)
        }
        Button { text = QuickAddInput.completing(text, with: row) } label: {
          HStack(spacing: 8) {
            Image(systemName: row.kind == .reminderList ? "list.bullet" : "calendar")
              .font(.system(size: 11, weight: .semibold)).foregroundStyle(row.kind == .reminderList ? Color.blue : Color.red)
              .frame(width: 12)
            Text(row.name).font(IslandFont.body).foregroundStyle(IslandInk.primary).lineLimit(1)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10).frame(height: 28).frame(maxWidth: .infinity)
          .background(index == highlighted ? IslandFill.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.bottom, 4).padding(.horizontal, 4)
    .frame(width: 210, alignment: .leading)
    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous).strokeBorder(IslandFill.hairline))
    .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
    .transition(.islandDrop)
  }

  private func move(_ delta: Int) -> KeyPress.Result {
    guard let rows = menu, !rows.isEmpty else { return .ignored }
    highlighted = (highlighted + delta + rows.count) % rows.count
    return .handled
  }

  private func commit() {
    if let rows = menu, rows.indices.contains(highlighted) {
      text = QuickAddInput.completing(text, with: rows[highlighted])
      return
    }
    submit()
  }
}
