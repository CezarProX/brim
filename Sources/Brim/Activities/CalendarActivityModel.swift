import AppKit
import EventKit

enum MeetingLink {
  static func validated(_ text: String) -> URL? {
    guard text.count <= 4096, let url = URL(string: text), url.scheme == "https",
      url.user == nil, url.password == nil, let host = url.host?.lowercased(),
      ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
        .contains(where: { host == $0 || host.hasSuffix("." + $0) })
    else { return nil }
    return url
  }

  static func find(in text: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    let bounded = String(text.prefix(20_000))
    return detector.matches(in: bounded, range: NSRange(bounded.startIndex..., in: bounded))
      .compactMap { $0.url.flatMap { validated($0.absoluteString) } }.first
  }
}

struct CalendarMeeting: Identifiable, Equatable {
  let id: String
  let title: String
  let startsAt: Date
  let endsAt: Date
  let calendar: String
  let joinURL: URL?
}

@MainActor
final class CalendarActivityModel: ObservableObject {
  static let shared = CalendarActivityModel()
  @Published private(set) var meeting: CalendarMeeting?
  func setMeeting(_ value: CalendarMeeting?) { meeting = value }
  @Published var status = "Connect Calendar to see your next meeting."
  @Published private(set) var isWorking = false
  /// The next two weeks of events and due reminders, grouped by day.
  @Published var agenda: [CalendarAgendaDay] = []
  /// An event the user chose with "Count down to this"; it overrides the automatic next meeting.
  @Published var pinned: PinnedCountdown? = PinnedCountdownStore.load()
  var agendaEvents: [CalendarAgendaItem] = []
  var agendaReminders: [CalendarAgendaItem] = []
  let eventStore = EKEventStore()
  private var store: EKEventStore { eventStore }
  private var timer: Timer?
  private var observer: NSObjectProtocol?
  var enabled: Bool { AppSettings.shared.calendarActivityEnabled }

  func start() {
    guard timer == nil, enabled else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    observer = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }

  func connect() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      guard try await store.requestFullAccessToEvents() else {
        status =
          "Calendar access is off. Enable Brim in System Settings → Privacy & Security → Calendars."
        return
      }
      AppSettings.shared.calendarActivityEnabled = true
      store.reset()
      start()
      refresh()
    } catch { status = "Couldn’t connect Calendar: \(error.localizedDescription)" }
  }

  func disconnect() {
    stop()
    AppSettings.shared.calendarActivityEnabled = false
    meeting = nil
    agenda = []
    status = "Calendar is disconnected."
  }

  func refresh(now: Date = .now) {
    guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      meeting = nil
      if enabled { status = "Calendar access is required." }
      return
    }
    let predicate = store.predicateForEvents(
      withStart: now.addingTimeInterval(-3600),
      end: now.addingTimeInterval(86_400), calendars: nil)
    let next = store.events(matching: predicate).filter {
      !$0.isAllDay && $0.endDate > now && $0.status != .canceled
        && !($0.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined }
          ?? false)
    }.sorted { $0.startDate < $1.startDate }.first
    meeting = next.map {
      CalendarMeeting(
        id: $0.eventIdentifier ?? $0.calendarItemIdentifier,
        title: String(($0.title ?? "Meeting").prefix(200)),
        startsAt: $0.startDate, endsAt: $0.endDate, calendar: $0.calendar.title,
        joinURL: MeetingLink.find(
          in: [$0.url?.absoluteString, $0.location, $0.notes].compactMap { $0 }.joined(
            separator: "\n")))
    }
    applyPinned(now: now)
    status = meeting == nil ? "No upcoming events in the next 24 hours." : "Calendar connected"
    refreshAgenda(now: now)
  }

  /// The island shows a meeting from 10 minutes before it starts until it ends.
  static let leadTime: TimeInterval = 600

  var isLive: Bool {
    guard let meeting else { return false }
    if let pinned, pinned.eventID == meeting.id { return CountdownPolicy.isVisible(pinned, now: .now) }
    return CountdownPolicy.isMeetingLive(start: meeting.startsAt, end: meeting.endsAt, now: .now, lead: Self.leadTime)
  }

  func join(_ expectedID: String) {
    refresh()
    guard let meeting, meeting.id == expectedID, let url = meeting.joinURL else { return }
    NSWorkspace.shared.open(url)
  }
}
