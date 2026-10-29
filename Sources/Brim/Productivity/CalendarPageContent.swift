import SwiftUI

/// Callbacks and data the calendar page needs; keeps the layout testable without EventKit.
struct CalendarPageActions {
  var completeReminder: (String) -> Void = { _ in }
  var completeThings: (ThingsTodo) -> Void = { _ in }
  var save: (QuickAddPlan) -> Bool = { _ in false }
  var toggleCountdown: (CalendarAgendaItem) -> Void = { _ in }
  var openInCalendar: (CalendarAgendaItem) -> Void = { _ in }
  var join: (URL) -> Void = { _ in }
  var showReminders: () -> Void = {}
}

/// Agenda beside the month grid, with an iPhone-style date header.
struct CalendarPageContent: View {
  let agenda: [CalendarAgendaDay]
  let todos: [ThingsTodo]
  let destinations: [QuickAddDestination]
  let calendar: Calendar
  let showWeekNumbers: Bool
  let remindersEnabled: Bool
  let pinnedEventID: String?
  let now: Date
  let actions: CalendarPageActions
  @State private var month: Date
  @State private var selectedDay: Date?
  @State private var adding: Bool
  @State private var draft: String
  @State private var detail: CalendarAgendaItem?
  @State private var direction: Edge = .trailing
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    agenda: [CalendarAgendaDay], todos: [ThingsTodo] = [], destinations: [QuickAddDestination] = [],
    calendar: Calendar = .current, showWeekNumbers: Bool = true, remindersEnabled: Bool = true,
    pinnedEventID: String? = nil, now: Date = .now, actions: CalendarPageActions = .init(),
    adding: Bool = false, draft: String = "", detail: CalendarAgendaItem? = nil, selectedDay: Date? = nil
  ) {
    self.agenda = agenda
    self.todos = todos
    self.destinations = destinations
    self.calendar = calendar
    self.showWeekNumbers = showWeekNumbers
    self.remindersEnabled = remindersEnabled
    self.pinnedEventID = pinnedEventID
    self.now = now
    self.actions = actions
    _month = State(initialValue: now)
    _selectedDay = State(initialValue: selectedDay)
    _adding = State(initialValue: adding)
    _draft = State(initialValue: draft)
    _detail = State(initialValue: detail)
  }

  private var shownDay: Date { selectedDay ?? now }
  private let red = IslandTint.color(for: .calendar)

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header.zIndex(2)
      HStack(alignment: .top, spacing: IslandSpace.m) {
        agendaColumn.frame(maxWidth: .infinity, alignment: .topLeading)
        CalendarMonthGrid(
          month: month, calendar: calendar, today: now, showWeekNumbers: showWeekNumbers, selectedDay: selectedDay,
          busyDays: Set(agenda.map { calendar.startOfDay(for: $0.day) }), onSelect: select
        )
        .id(calendar.component(.month, from: month)).transition(.push(from: direction))
        .frame(width: showWeekNumbers ? 218 : 196).clipped()
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let item = detail {
        CalendarEventCard(
          item: item, pinned: pinnedEventID == item.id.components(separatedBy: "#")[0], now: now,
          toggleCountdown: { actions.toggleCountdown(item); detail = nil },
          openInCalendar: { actions.openInCalendar(item) }, join: actions.join,
          close: { withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { detail = nil } }
        )
        .padding(.bottom, 2).transition(.islandDrop).zIndex(3)
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 6) {
      if adding {
        CalendarQuickAddBar(text: $draft, destinations: destinations, submit: submit)
          .frame(maxWidth: 360).transition(.islandDrop)
      } else {
        Text(shownDay, format: .dateTime.weekday(.abbreviated).day()).textCase(.uppercase)
          .font(.system(size: 14, weight: .bold)).foregroundStyle(red)
        Text("W\(CalendarWeekMath.weekNumber(of: shownDay, calendar: calendar))")
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(red.opacity(0.7))
      }
      Spacer(minLength: 0)
      if adding {
        headerButton("xmark", label: "Cancel") {
          withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { adding.toggle() }
        }
      } else {
        Button {
          withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { adding.toggle() }
        } label: { Label("New", systemImage: "plus") }
        .buttonStyle(IslandPillStyle(compact: true)).help("New event or reminder")
        .accessibilityLabel("New event or reminder")
      }
      headerButton("calendar.badge.clock", label: "Jump to today") {
        direction = .leading
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { month = now; selectedDay = nil }
      }
      IslandGlyphButton(symbol: "chevron.left", label: "Previous month", size: 28) { shift(-1) }
      Text(month, format: .dateTime.month(.abbreviated)).textCase(.uppercase)
        .font(.system(size: 14, weight: .bold)).foregroundStyle(red).frame(minWidth: 40)
        .contentTransition(.opacity)
      IslandGlyphButton(symbol: "chevron.right", label: "Next month", size: 28) { shift(1) }
    }
    .frame(height: 30)
  }

  private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(IslandInk.secondary)
        .frame(width: 28, height: 28).background(IslandFill.raised, in: Circle()).contentShape(Circle())
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(IslandPressStyle()).help(label).accessibilityLabel(label)
  }

  // MARK: Agenda

  private var visibleDays: [CalendarAgendaDay] {
    guard let selectedDay else { return agenda }
    return agenda.filter { calendar.isDate($0.day, inSameDayAs: selectedDay) }
  }

  private var agendaColumn: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        if (selectedDay == nil || calendar.isDate(selectedDay ?? now, inSameDayAs: now)), !todos.isEmpty {
          ForEach(todos.prefix(8)) { todo in
            ThingsRow(todo: todo) { actions.completeThings(todo) }.transition(.islandDrop)
          }
        }
        if visibleDays.isEmpty && todos.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(selectedDay == nil ? "Nothing in the next two weeks" : "Nothing on this day")
              .font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
            Button {
              withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { adding = true }
            } label: { Label("Add an event", systemImage: "plus") }
            .buttonStyle(IslandPillStyle(prominent: true, tint: red))
          }
          .padding(.top, IslandSpace.m)
        }
        ForEach(Array(visibleDays.enumerated()), id: \.element.id) { index, day in
          if !(index == 0 && calendar.isDate(day.day, inSameDayAs: now)) {
            Text(heading(for: day.day)).font(.system(size: 12, weight: .semibold)).tracking(0.4)
              .foregroundStyle(IslandInk.tertiary).padding(.top, 4)
          }
          ForEach(day.items) { item in
            AgendaRow(
              item: item, open: { withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { detail = item } },
              join: actions.join, complete: { actions.completeReminder(item.id) },
              pinned: pinnedEventID == item.id.components(separatedBy: "#")[0]
            )
            .transition(.islandDrop)
          }
        }
        if !remindersEnabled {
          Button("Show reminders", action: actions.showReminders)
            .buttonStyle(IslandPillStyle(compact: true)).padding(.top, 4)
        }
      }
      .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: visibleDays)
    }
    .scrollIndicators(.hidden)
  }

  private func heading(for day: Date) -> String {
    let name: String
    if calendar.isDate(day, inSameDayAs: now) { name = "TODAY" }
    else if calendar.isDateInTomorrow(day) { name = "TOMORROW" }
    else { name = day.formatted(.dateTime.weekday(.abbreviated).day()).uppercased() }
    let week = CalendarWeekMath.weekNumber(of: day, calendar: calendar)
    return week == CalendarWeekMath.weekNumber(of: now, calendar: calendar) ? name : "\(name) · W\(week)"
  }

  // MARK: Actions

  private func select(_ day: Date) {
    withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
      selectedDay = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } == true ? nil : day
    }
  }

  private func shift(_ months: Int) {
    direction = months > 0 ? .trailing : .leading
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
  }

  private func submit() {
    guard let plan = QuickAddPlan.make(draft, destinations: destinations, now: now, calendar: calendar),
      actions.save(plan)
    else { return }
    draft = ""
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { adding = false }
  }
}
