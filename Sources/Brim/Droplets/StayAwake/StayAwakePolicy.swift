import Foundation

/// A weekly window in which the Mac should stay awake. Times are minutes after midnight and the
/// window may wrap past midnight (22:00 to 06:00).
struct StayAwakeSchedule: Equatable, Sendable {
  var startMinutes: Int
  var endMinutes: Int
  /// Calendar weekday numbers: 1 Sunday ... 7 Saturday. For a window that wraps midnight the
  /// day is the one it starts on.
  var days: Set<Int>

  func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    guard startMinutes != endMinutes else { return false }
    let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
    let minutes = hour * 60 + minute
    if startMinutes < endMinutes {
      return days.contains(weekday) && minutes >= startMinutes && minutes < endMinutes
    }
    if minutes >= startMinutes { return days.contains(weekday) }
    let previous = weekday == 1 ? 7 : weekday - 1
    return minutes < endMinutes && days.contains(previous)
  }
}

struct StayAwakeOptions: Equatable, Sendable {
  /// Keep the display lit too; off allows the screen to sleep while the Mac keeps running.
  var keepDisplayOn = true
  var onPowerAdapter = false
  var schedule: StayAwakeSchedule?
  var lidClosedOnPower = false
}

enum StayAwakePolicy {
  /// Whether a trigger (power adapter or schedule) wants the Mac awake right now.
  static func triggerWantsAwake(_ options: StayAwakeOptions, onAdapter: Bool, now: Date, calendar: Calendar = .current) -> Bool {
    if options.onPowerAdapter && onAdapter { return true }
    return options.schedule?.contains(now, calendar: calendar) ?? false
  }

  /// Closing the lid keeps the Mac running only while awake, on the adapter, and opted in.
  static func lidClosedWanted(_ options: StayAwakeOptions, awake: Bool, onAdapter: Bool) -> Bool {
    options.lidClosedOnPower && awake && onAdapter
  }

  /// The AppleScript that switches lid-closed operation, which needs an administrator password.
  static func lidClosedScript(enable: Bool) -> String {
    "do shell script \"/usr/bin/pmset -a disablesleep \(enable ? 1 : 0)\" with administrator privileges"
  }

  /// "9:00 AM"-style label for a minutes-after-midnight value.
  static func label(minutes: Int) -> String {
    let clamped = min(1439, max(0, minutes))
    var parts = DateComponents()
    parts.hour = clamped / 60
    parts.minute = clamped % 60
    let date = Calendar.current.date(from: parts) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
  }
}

extension AppSettings {
  var stayAwakeOptions: StayAwakeOptions {
    StayAwakeOptions(
      keepDisplayOn: stayAwakeKeepDisplayOn, onPowerAdapter: stayAwakeOnPowerAdapter,
      schedule: stayAwakeScheduleEnabled
        ? StayAwakeSchedule(startMinutes: stayAwakeScheduleStart, endMinutes: stayAwakeScheduleEnd, days: stayAwakeScheduleDays) : nil,
      lidClosedOnPower: stayAwakeLidClosedOnPower)
  }
}
