import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct ProductivityRenderTests {
  static let size = CGSize(width: 560, height: 200)

  private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    c.firstWeekday = 2
    return c
  }

  private var now: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 5))! }

  private func at(_ day: Int, _ h: Int, _ m: Int, minutes: Int = 30) -> (Date, Date) {
    let start = utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    return (start, start.addingTimeInterval(TimeInterval(minutes * 60)))
  }

  private func event(_ title: String, _ day: Int, _ h: Int, _ m: Int, minutes: Int = 30, color: Color, join: Bool = false, allDay: Bool = false, endDay: Int? = nil) -> CalendarAgendaItem {
    var (s, e) = at(day, h, m, minutes: minutes)
    if allDay, let endDay { e = utc.date(from: DateComponents(year: 2026, month: 10, day: endDay))! }
    return CalendarAgendaItem(
      id: title, kind: .event, title: title, start: allDay ? utc.startOfDay(for: s) : s, end: e, isAllDay: allDay, color: color,
      joinURL: join ? URL(string: "https://meet.google.com/abc") : nil, location: "Studio B", notes: "Bring the launch checklist.",
      calendarName: "Work")
  }

  private var agenda: [CalendarAgendaDay] {
    let blue = Color(red: 0.4, green: 0.5, blue: 0.95), orange = Color(red: 1, green: 0.45, blue: 0.3)
    let reminder = CalendarAgendaItem(
      id: "r1", kind: .reminder, title: "Ship the landing page", start: at(14, 9, 0).0, end: nil, isAllDay: true,
      color: .blue, joinURL: nil)
    let items = [
      event("Offsite", 13, 0, 0, color: .green, allDay: true, endDay: 15),
      event("Team standup", 13, 9, 30, minutes: 15, color: blue),
      event("Launch review", 13, 10, 0, minutes: 60, color: blue, join: true),
      event("Lunch with Maya", 13, 12, 30, minutes: 75, color: orange),
      event("Design sync", 13, 14, 0, color: blue),
      reminder,
      event("Product launch", 15, 9, 0, minutes: 60, color: blue),
    ]
    return CalendarAgendaBuilder.groupExpanded(items, calendar: utc)
  }

  private let destinations = [
    QuickAddDestination(id: "1", name: "My Tasks", kind: .reminderList),
    QuickAddDestination(id: "2", name: "Things 3 · Launch", kind: .reminderList),
    QuickAddDestination(id: "3", name: "Personal", kind: .calendar),
    QuickAddDestination(id: "4", name: "Work", kind: .calendar),
  ]

  @Test func monthAndAgenda() async throws {
    let view = CalendarPageContent(agenda: agenda, destinations: destinations, calendar: utc, now: now)
    _ = try await Self.render(view, name: "calendar-month-agenda")
  }

  @Test func eventDetailsCard() async throws {
    let item = agenda[0].items.first { $0.title == "Lunch with Maya" }!
    let view = CalendarPageContent(agenda: agenda, destinations: destinations, calendar: utc, now: now, detail: item)
    _ = try await Self.render(view, name: "calendar-event-card")
  }

  @Test func quickAddWithAtMenu() async throws {
    let view = CalendarPageContent(
      agenda: agenda, destinations: destinations, calendar: utc, now: now, adding: true,
      draft: "Lunch with Sam tomorrow at 1pm @")
    _ = try await Self.render(view, name: "calendar-quickadd-menu")
  }

  @Test func pomodoroTape() async throws {
    let store = FocusSessionStore(defaults: UserDefaults(suiteName: "pomodoro-render-\(UUID())")!)
    for day in [-2, -1, 0] { store.recordSession(at: Date().addingTimeInterval(TimeInterval(day * 86_400))) }
    let model = FocusTimerModel()
    _ = try await Self.render(PomodoroPanelView(model: model, store: store), name: "pomodoro-tape")
    model.startPomodoro(focusMinutes: 25, breakMinutes: 5)
    defer { model.stop() }
    _ = try await Self.render(PomodoroPanelView(model: model, store: store), name: "pomodoro-running")
  }

  @Test func notesPanel() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-render-\(UUID())")
    let notes = NotesModel(directory: dir)
    let a = notes.create()
    notes.update(a.id, text: "# Launch checklist\n- [x] Draft copy\n- [ ] **Record** the demo\n> ship Friday\nSee `notes.md` and *italics*")
    let b = notes.create()
    notes.update(b.id, text: "Groceries\nmilk, eggs")
    notes.togglePin(b.id)
    notes.selectedID = a.id
    let view = NotesPanelView(notes: notes, obsidian: ObsidianModel(vaultPath: nil, obsidianConfig: nil), mode: .notes, preview: true)
    _ = try await Self.render(view, name: "notes-preview")
    _ = try await Self.render(NotesPanelView(notes: notes, obsidian: ObsidianModel(vaultPath: nil, obsidianConfig: nil), mode: .notes, preview: false), name: "notes-edit")
    try? FileManager.default.removeItem(at: dir)
  }

  static func render<V: View>(_ view: V, name: String, size: CGSize = size) async throws -> NSBitmapImageRep {
    let pad: CGFloat = 12
    let framed = view.frame(width: size.width, height: size.height, alignment: .topLeading)
      .padding(pad).foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: framed)
    let total = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: total), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: total)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent(".renders", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
    return bitmap
  }
}
