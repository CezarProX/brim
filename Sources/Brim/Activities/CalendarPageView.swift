import AppKit
import EventKit
import SwiftUI

/// The Calendar droplet: agenda + month grid, quick add with "@" destinations, event details,
/// "Count down to this", and optional Things 3 to-dos. Falls back to the permission prompt.
@MainActor
struct CalendarPageView: View {
  @ObservedObject var model: CalendarActivityModel
  @ObservedObject private var things = ThingsModel.shared
  @ObservedObject private var settingsTick = CalendarSettingsTick.shared

  /// Tile for the Widgets page.
  static let tile = (title: "Calendar", symbol: "calendar", tint: Color(nsColor: .systemRed))

  var body: some View {
    // Access can be revoked (or reset) while the toggle is still on; then the prompt comes back.
    if model.enabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess {
      TimelineView(.periodic(from: .now, by: 30)) { context in
        CalendarPageContent(
          agenda: model.agenda, todos: things.enabled ? things.todos : [],
          destinations: model.quickAddDestinations(), calendar: model.weekCalendar,
          showWeekNumbers: AppSettings.shared.calendarWeekNumbers, remindersEnabled: model.remindersEnabled,
          pinnedEventID: model.pinned?.eventID, now: context.date, actions: actions
        )
        .id(settingsTick.revision)
      }
      .task { await things.refresh() }
    } else {
      CalendarActivityView(model: model)
    }
  }

  private var actions: CalendarPageActions {
    CalendarPageActions(
      completeReminder: { model.complete(reminderID: $0) },
      completeThings: { todo in Task { await things.complete(todo) } },
      save: { model.save($0) },
      toggleCountdown: { item in
        if model.isPinned(item) { model.clearCountdown() } else { model.countdown(to: item) }
      },
      openInCalendar: { item in
        if let url = URL(string: "calshow:\(item.start.timeIntervalSinceReferenceDate)") { NSWorkspace.shared.open(url) }
      },
      join: { NSWorkspace.shared.open($0) },
      showReminders: { Task { await model.connectReminders() } })
  }
}

/// Bumps when week-start or week-number settings change so the open page rebuilds.
@MainActor
final class CalendarSettingsTick: ObservableObject {
  static let shared = CalendarSettingsTick()
  @Published private(set) var revision = 0
  func bump() { revision += 1 }
}
