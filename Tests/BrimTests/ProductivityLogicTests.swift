import Foundation
import Testing

@testable import Brim

private var utc: Calendar {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  c.firstWeekday = 2
  return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
  utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct QuickAddPlanTests {
  let dests = [
    QuickAddDestination(id: "1", name: "My Tasks", kind: .reminderList),
    QuickAddDestination(id: "2", name: "Things 3 · Launch", kind: .reminderList),
    QuickAddDestination(id: "3", name: "Work", kind: .calendar),
    QuickAddDestination(id: "4", name: "Personal", kind: .calendar),
  ]
  let now = date(2026, 10, 13, 9)

  @Test func openAtOpensMenuWithQuery() {
    let input = QuickAddInput.split("Lunch with Sam tomorrow at 1pm @")
    #expect(input.openQuery == "")
    #expect(input.body == "Lunch with Sam tomorrow at 1pm")
    #expect(QuickAddInput.split("Lunch @Wo").openQuery == "Wo")
  }

  @Test func completedDestinationIsExtracted() {
    let input = QuickAddInput.split("Lunch with Sam tomorrow at 1pm @Work", known: ["Work"])
    #expect(input.destinationName == "Work")
    #expect(input.body == "Lunch with Sam tomorrow at 1pm")
    #expect(QuickAddInput.split("Ship it @\"Things 3 · Launch\" friday").destinationName == "Things 3 · Launch")
  }

  @Test func menuListsRemindersBeforeCalendarsAndFilters() {
    let all = QuickAddDestinations.menu(matching: "", in: dests)
    #expect(all.map(\.name) == ["My Tasks", "Things 3 · Launch", "Work", "Personal"])
    #expect(QuickAddDestinations.menu(matching: "wo", in: dests).map(\.name) == ["Work"])
  }

  @Test func pickingFromMenuInsertsToken() {
    let text = QuickAddInput.completing("Lunch tomorrow at 1pm @Th", with: dests[1])
    #expect(text == "Lunch tomorrow at 1pm @\"Things 3 · Launch\" ")
    #expect(QuickAddInput.split(text).destinationName == "Things 3 · Launch")
  }

  @Test func eventGoesToNamedCalendar() throws {
    let plan = try #require(QuickAddPlan.make("Lunch with Sam tomorrow at 1pm @work", destinations: dests, now: now, calendar: utc))
    #expect(plan.destination?.name == "Work")
    guard case .event(let draft) = plan.output else { Issue.record("expected event"); return }
    #expect(draft.title == "Lunch with Sam")
    #expect(!draft.isAllDay)
  }

  @Test func reminderListMakesReminderEvenWithoutDate() throws {
    let plan = try #require(QuickAddPlan.make("Buy milk @My", destinations: dests, now: now, calendar: utc))
    #expect(plan.output == .reminder(title: "Buy milk", due: nil, hasTime: false))
    #expect(plan.destination?.kind == .reminderList)
  }

  @Test func noDestinationNoDateIsRejected() {
    #expect(QuickAddPlan.make("Buy milk", destinations: dests, now: now, calendar: utc) == nil)
    #expect(QuickAddPlan.make("Buy milk @", destinations: dests, now: now, calendar: utc) == nil)
  }
}

struct CountdownPolicyTests {
  let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test func labelsScaleWithDistance() {
    #expect(CountdownPolicy.label(until: start, now: start.addingTimeInterval(-(86_400 + 23 * 3600 + 60))) == "1d 23h")
    #expect(CountdownPolicy.label(until: start, now: start.addingTimeInterval(-(2 * 3600 + 5 * 60))) == "2h 05m")
    #expect(CountdownPolicy.label(until: start, now: start.addingTimeInterval(-12 * 60)) == "12 min")
    #expect(CountdownPolicy.label(until: start, now: start.addingTimeInterval(-259)) == "4:19")
    #expect(CountdownPolicy.label(until: start, now: start) == "Now")
    #expect(CountdownPolicy.phrase(until: start, now: start.addingTimeInterval(-300)) == "in 5:00")
  }

  @Test func ringFillsInLastTenMinutesThenDrainsDuringEvent() {
    let end = start.addingTimeInterval(3600)
    #expect(CountdownPolicy.ringProgress(start: start, end: end, now: start.addingTimeInterval(-3600)) == 0)
    #expect(CountdownPolicy.ringProgress(start: start, end: end, now: start.addingTimeInterval(-300)) == 0.5)
    #expect(CountdownPolicy.ringProgress(start: start, end: end, now: start) == 1)
    #expect(CountdownPolicy.ringProgress(start: start, end: end, now: start.addingTimeInterval(1800)) == 0.5)
  }

  @Test func pinnedCountdownExpiresAfterStart() {
    let pin = PinnedCountdown(eventID: "e", title: "t", start: start, end: start.addingTimeInterval(3600))
    #expect(CountdownPolicy.isVisible(pin, now: start.addingTimeInterval(-86_400)))
    #expect(CountdownPolicy.isVisible(pin, now: start.addingTimeInterval(30)))
    #expect(!CountdownPolicy.isVisible(pin, now: start.addingTimeInterval(61)))
  }

  @Test func autoMeetingWindowIsTenMinutesUntilEnd() {
    let end = start.addingTimeInterval(1800)
    #expect(!CountdownPolicy.isMeetingLive(start: start, end: end, now: start.addingTimeInterval(-601)))
    #expect(CountdownPolicy.isMeetingLive(start: start, end: end, now: start.addingTimeInterval(-600)))
    #expect(!CountdownPolicy.isMeetingLive(start: start, end: end, now: end))
  }
}

struct WeekMathTests {
  @Test func weekStartSettingChangesGridAndSymbols() {
    let sunday = CalendarWeekMath.calendar(weekStart: 1, base: utc)
    let monday = CalendarWeekMath.calendar(weekStart: 2, base: utc)
    #expect(CalendarWeekMath.weekdaySymbols(calendar: monday).first == "M")
    #expect(CalendarWeekMath.weekdaySymbols(calendar: sunday).first == "S")
    let grid = CalendarAgendaBuilder.monthGrid(for: date(2026, 10, 13), calendar: monday)
    #expect(grid.count == 42)
    #expect(monday.component(.weekday, from: grid[0]) == 2)
    #expect(CalendarAgendaBuilder.monthGrid(for: date(2026, 10, 13), calendar: sunday).first.map { sunday.component(.weekday, from: $0) } == 1)
  }

  @Test func isoWeekNumber() {
    #expect(CalendarWeekMath.weekNumber(of: date(2026, 10, 13), calendar: utc) == 42)
    #expect(CalendarWeekMath.weekNumber(of: date(2026, 1, 1), calendar: utc) == 1)
    #expect(CalendarWeekMath.weeks(of: CalendarAgendaBuilder.monthGrid(for: date(2026, 10, 1), calendar: utc)).count == 6)
  }

  @Test func multiDayEventAppearsOnEveryDayAndAllDayEndsInclusive() {
    let trip = CalendarAgendaItem(
      id: "trip", kind: .event, title: "Trip", start: date(2026, 10, 13), end: date(2026, 10, 16), isAllDay: true,
      color: .red, joinURL: nil)
    let days = CalendarAgendaBuilder.groupExpanded([trip], calendar: utc)
    #expect(days.count == 3)
    #expect(days.map { $0.items[0].spanLabel } == ["Day 1/3", "Day 2/3", "Day 3/3"])
    let single = CalendarAgendaItem(
      id: "a", kind: .event, title: "Holiday", start: date(2026, 10, 13), end: date(2026, 10, 14), isAllDay: true,
      color: .red, joinURL: nil)
    #expect(CalendarAgendaBuilder.groupExpanded([single], calendar: utc).count == 1)
    let overnight = CalendarAgendaItem(
      id: "o", kind: .event, title: "Flight", start: date(2026, 10, 13, 22), end: date(2026, 10, 14, 6), isAllDay: false,
      color: .red, joinURL: nil)
    #expect(CalendarAgendaBuilder.groupExpanded([overnight], calendar: utc).count == 2)
  }
}

struct PomodoroTapeMathTests {
  typealias T = PomodoroTapeMath

  @Test func draggingLeftIncreasesAndClamps() {
    #expect(T.rawMinutes(start: 25, translation: -60) == 35)
    #expect(T.rawMinutes(start: 25, translation: 60) == 15)
    #expect(T.rawMinutes(start: 5, translation: 1000) == 1)
    #expect(T.rawMinutes(start: 470, translation: -1000) == 480)
  }

  @Test func detentsStickWithinFourPointsOnly() {
    #expect(T.snapped(24.5, detents: T.focusDetents) == 25)  // 3pt away
    #expect(T.snapped(24.2, detents: T.focusDetents) == 24)  // 4.8pt away
    #expect(T.snapped(30.4, detents: T.focusDetents) == 30)
    #expect(T.snapped(0, detents: T.focusDetents) == 1)
  }

  @Test func ticksAndHaptics() {
    #expect(T.tick(for: 25, detents: T.focusDetents) == .detent)
    #expect(T.tick(for: 30, detents: T.focusDetents) == .major)
    #expect(T.tick(for: 31, detents: T.focusDetents) == .minor)
    #expect(T.hapticTick(from: 30, to: 30, detents: []) == nil)
    #expect(T.hapticTick(from: 24, to: 25, detents: T.focusDetents) == .detent)
  }

  @Test func geometryAndLabels() {
    #expect(T.offset(of: 30, centeredOn: 25) == 30)
    #expect(T.visibleMinutes(centeredOn: 3, width: 120).lowerBound == 1)
    #expect(T.label(minutes: 25) == "25 min")
    #expect(T.label(minutes: 90) == "1 h 30 min")
    #expect(T.label(minutes: 480) == "8 h")
  }
}

struct FocusStreakTests {
  private func log(_ days: [(Int, Int)]) -> FocusSessionLog {
    days.reduce(FocusSessionLog()) { $0.recording(at: date(2026, days[0].0 == 0 ? 10 : 10, $1.0, 12), calendar: utc) }
  }

  @Test func consecutiveDaysCount() {
    let l = log([(11, 1), (12, 1), (13, 1)])
    #expect(l.streak(today: date(2026, 10, 13, 18), calendar: utc) == 3)
  }

  @Test func emptyTodayKeepsStreakAliveButMissedDayBreaksIt() {
    let l = log([(11, 1), (12, 1)])
    #expect(l.streak(today: date(2026, 10, 13, 8), calendar: utc) == 2)
    #expect(l.streak(today: date(2026, 10, 14, 8), calendar: utc) == 0)
  }

  @Test func gapEndsRunAndMultipleSessionsCountOnce() {
    var l = log([(8, 1), (10, 1), (11, 1)])
    l = l.recording(at: date(2026, 10, 11, 15), calendar: utc)
    #expect(l.sessions(on: date(2026, 10, 11), calendar: utc) == 2)
    #expect(l.streak(today: date(2026, 10, 11, 20), calendar: utc) == 2)
  }

  @MainActor @Test func completingFocusRecordsSessionThroughHook() {
    var recorded: [Date] = []
    let model = FocusTimerModel(hooks: .init(sessionCompleted: { recorded.append($0) }))
    defer { model.stop() }
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    model.startPomodoro(focusMinutes: 25, breakMinutes: 5, now: start)
    model.tick(now: start.addingTimeInterval(25 * 60))
    model.tick(now: start.addingTimeInterval(30 * 60))  // end of the break is not a session
    #expect(recorded.count == 1)
  }
}

struct ThingsBridgeTests {
  let fixture = "ABC123xyz\tWrite report\tLaunch\t20261015\tWork,Urgent\n"
    + "DEF456\tCall mum\t\t\t\n"
    + "bad id with spaces\tIgnored\t\t\t\n"
    + "GHI789\t\t\t\t\n"
    + "JKL012\tNo tags column\tHome\n"

  @Test func parsesFixtureAndSkipsMalformedLines() {
    let todos = ThingsScripts.parse(fixture)
    #expect(todos.map(\.id) == ["ABC123xyz", "DEF456", "JKL012"])
    #expect(todos[0].project == "Launch")
    #expect(todos[0].tags == ["Work", "Urgent"])
    #expect(todos[0].due.map { Calendar.current.component(.day, from: $0) } == 15)
    #expect(todos[1].project == nil && todos[1].due == nil && todos[1].tags.isEmpty)
    #expect(todos[2].project == "Home")
  }

  @Test func completeScriptRejectsUnsafeIDs() {
    #expect(ThingsScripts.complete(id: "ABC123")?.contains("to do id \"ABC123\"") == true)
    #expect(ThingsScripts.complete(id: "x\" & (do shell script \"id\") & \"") == nil)
  }

  @Test func addURLEncodesTitle() throws {
    let url = try #require(ThingsScripts.addURL(title: "Buy milk & eggs"))
    #expect(url.absoluteString.hasPrefix("things:///add?title=Buy%20milk%20%26%20eggs"))
    #expect(url.absoluteString.contains("when=today"))
    #expect(ThingsScripts.addURL(title: "  ") == nil)
  }
}

struct NotesLogicTests {
  @Test func markdownBlocks() {
    let blocks = MarkdownLite.blocks("# Title\n- item\n- [ ] todo\n- [x] done\n> quote\n```\ncode\n```\nplain **bold**")
    #expect(blocks == [
      .heading(level: 1, text: "Title"), .bullet(text: "item"), .checkbox(done: false, text: "todo"),
      .checkbox(done: true, text: "done"), .quote(text: "quote"), .blank, .code(text: "code"), .blank,
      .paragraph(text: "plain **bold**"),
    ])
    #expect(MarkdownLite.toggleCheckbox(in: "a\n- [ ] b", line: 1) == "a\n- [x] b")
    #expect(MarkdownLite.toggleCheckbox(in: "- [x] b", line: 0) == "- [ ] b")
  }

  @Test func searchAndPinOrdering() {
    let a = IslandNote(id: UUID(), text: "Groceries\nmilk", edited: .now)
    let b = IslandNote(id: UUID(), text: "Ideas", edited: .now, pinned: true)
    #expect(NotesModel.filter([a, b], query: "MILK") == [a])
    #expect(NotesModel.filter([a, b], query: " ") == [a, b])
    #expect(NotesModel.ordered([a, b]).first == b)
  }

  @Test func oldNotesDecodeWithoutPinField() throws {
    let json = #"[{"id":"\#(UUID().uuidString)","text":"hi","edited":0}]"#
    let notes = try JSONDecoder().decode([IslandNote].self, from: Data(json.utf8))
    #expect(notes[0].pinned == false && notes[0].appleID == nil)
  }

  @Test func appleNotesParseAndSyncPlan() {
    let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let output = "x-coredata://A/ICNote/p1\u{1F}-120\u{1F}Hello\nworld\u{1E}x-coredata://A/ICNote/p2\u{1F}-5\u{1F}New one\u{1E}"
    let remote = AppleNotesBridge.parse(output, now: now)
    #expect(remote.count == 2)
    #expect(remote[0].text == "Hello\nworld")
    #expect(remote[0].modified == now.addingTimeInterval(-120))

    let synced = IslandNote(id: UUID(), text: "# Hello\nold", edited: now.addingTimeInterval(-600), appleID: remote[0].id)
    let localOnly = IslandNote(id: UUID(), text: "Local", edited: now)
    let plan = NotesSyncPlan.make(local: [synced, localOnly], remote: remote)
    #expect(plan.pullUpdate.map(\.0) == [synced.id])
    #expect(plan.pushCreate == [localOnly.id])
    #expect(plan.pullCreate.map(\.id) == [remote[1].id])
    let newer = IslandNote(id: synced.id, text: "# Hello\nlocal edit", edited: now, appleID: remote[0].id)
    #expect(NotesSyncPlan.make(local: [newer], remote: [remote[0]]).pushUpdate == [synced.id])
    let same = IslandNote(id: synced.id, text: "# Hello\nworld", edited: now, appleID: remote[0].id)
    #expect(NotesSyncPlan.make(local: [same], remote: [remote[0]]) == NotesSyncPlan(pullCreate: []))
    #expect(AppleNotesBridge.updateScript(id: "bad\"id", text: "x") == nil)
  }
}

struct ObsidianVaultTests {
  private func makeVault() throws -> (ObsidianVault, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: dir.appendingPathComponent("Daily"), withIntermediateDirectories: true)
    try fm.createDirectory(at: dir.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
    try fm.createDirectory(at: dir.appendingPathComponent(".trash"), withIntermediateDirectories: true)
    try "a".write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    try "b".write(to: dir.appendingPathComponent("Daily/B.md"), atomically: true, encoding: .utf8)
    try "x".write(to: dir.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
    try "t".write(to: dir.appendingPathComponent(".trash/T.md"), atomically: true, encoding: .utf8)
    return (ObsidianVault(root: dir), dir)
  }

  @Test func listsMarkdownSkippingHiddenAndOtherTypes() throws {
    let (vault, dir) = try makeVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(Set(vault.list().map(\.relativePath)) == ["A.md", "Daily/B.md"])
  }

  @Test func readWriteStaysInsideVault() throws {
    let (vault, dir) = try makeVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    try vault.write("hello", to: "New/Note.md")
    #expect(try vault.read("New/Note.md") == "hello")
    #expect(throws: ObsidianError.outsideVault) { try vault.read("../secret.md") }
    #expect(throws: ObsidianError.notMarkdown) { try vault.read("image.png") }
  }

  @Test func dailyNoteUsesVaultSettingsAndIsCreatedOnce() throws {
    let (vault, dir) = try makeVault()
    defer { try? FileManager.default.removeItem(at: dir) }
    let day = date(2026, 10, 13)
    #expect(vault.dailyNotePath(for: day, calendar: utc) == "2026-10-13.md")
    try #"{"folder":"Daily","format":"YYYY-MM-DD"}"#.write(
      to: dir.appendingPathComponent(".obsidian/daily-notes.json"), atomically: true, encoding: .utf8)
    let path = try vault.openDailyNote(for: day, calendar: utc)
    #expect(path == "Daily/2026-10-13.md")
    try vault.write("kept", to: path)
    try vault.openDailyNote(for: day, calendar: utc)
    #expect(try vault.read(path) == "kept")
  }
}
