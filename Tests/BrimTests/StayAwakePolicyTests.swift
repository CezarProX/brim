import Foundation
import Testing

@testable import Brim

struct StayAwakePolicyTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// 2026-10-26 is a Monday (weekday 2).
  private func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  @Test func daytimeWindowCoversOnlyItsHoursAndDays() {
    let weekdays = StayAwakeSchedule(startMinutes: 9 * 60, endMinutes: 18 * 60, days: [2, 3, 4, 5, 6])
    #expect(weekdays.contains(date(day: 26, 9), calendar: calendar))
    #expect(weekdays.contains(date(day: 26, 17, 59), calendar: calendar))
    #expect(!weekdays.contains(date(day: 26, 18), calendar: calendar))
    #expect(!weekdays.contains(date(day: 26, 8, 59), calendar: calendar))
    #expect(!weekdays.contains(date(day: 25, 12), calendar: calendar))  // Sunday
  }

  @Test func overnightWindowBelongsToTheDayItStarted() {
    let nights = StayAwakeSchedule(startMinutes: 22 * 60, endMinutes: 6 * 60, days: [6])  // starts Friday
    #expect(nights.contains(date(day: 30, 23), calendar: calendar))  // Friday 23:00
    #expect(nights.contains(date(day: 31, 5), calendar: calendar))  // Saturday 05:00, still Friday's window
    #expect(!nights.contains(date(day: 31, 23), calendar: calendar))  // Saturday night is not listed
    #expect(!nights.contains(date(day: 30, 5), calendar: calendar))  // Friday 05:00 belongs to Thursday's
  }

  @Test func emptyWindowNeverMatches() {
    #expect(!StayAwakeSchedule(startMinutes: 600, endMinutes: 600, days: Set(1...7)).contains(date(day: 26, 10), calendar: calendar))
  }

  @Test func triggersCombineAdapterAndSchedule() {
    var options = StayAwakeOptions()
    let noon = date(day: 26, 12)
    #expect(!StayAwakePolicy.triggerWantsAwake(options, onAdapter: true, now: noon, calendar: calendar))
    options.onPowerAdapter = true
    #expect(StayAwakePolicy.triggerWantsAwake(options, onAdapter: true, now: noon, calendar: calendar))
    #expect(!StayAwakePolicy.triggerWantsAwake(options, onAdapter: false, now: noon, calendar: calendar))
    options.schedule = StayAwakeSchedule(startMinutes: 11 * 60, endMinutes: 13 * 60, days: [2])
    #expect(StayAwakePolicy.triggerWantsAwake(options, onAdapter: false, now: noon, calendar: calendar))
  }

  @Test func lidClosedNeedsOptInAwakeAndAdapter() {
    var options = StayAwakeOptions()
    #expect(!StayAwakePolicy.lidClosedWanted(options, awake: true, onAdapter: true))
    options.lidClosedOnPower = true
    #expect(StayAwakePolicy.lidClosedWanted(options, awake: true, onAdapter: true))
    #expect(!StayAwakePolicy.lidClosedWanted(options, awake: false, onAdapter: true))
    #expect(!StayAwakePolicy.lidClosedWanted(options, awake: true, onAdapter: false))
  }

  @Test func lidScriptIsFixedAndPromptsForAdministrator() {
    #expect(StayAwakePolicy.lidClosedScript(enable: true) == "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges")
    #expect(StayAwakePolicy.lidClosedScript(enable: false).contains("disablesleep 0"))
  }

  @Test func optionsAreReadFromSettings() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-Awake-\(UUID().uuidString)")!)
    #expect(settings.stayAwakeOptions == StayAwakeOptions())
    settings.stayAwakeKeepDisplayOn = false
    settings.stayAwakeScheduleEnabled = true
    settings.stayAwakeScheduleDays = [2]
    let options = settings.stayAwakeOptions
    #expect(!options.keepDisplayOn && options.schedule?.days == [2] && options.schedule?.startMinutes == 540)
  }
}

struct LidClosedGateTests {
  @Test func onlyOneAdministratorPromptAtATime() {
    var gate = LidClosedGate()
    #expect(gate.shouldChange(wanted: true, active: false))
    gate.inFlight = true
    #expect(!gate.shouldChange(wanted: true, active: false))
    #expect(!gate.shouldChange(wanted: true, active: true))
  }

  @Test func aCancelledTurnOffIsNotRetriedUntilTheUserActs() {
    var gate = LidClosedGate()
    gate.finished(turningOn: false, succeeded: false)
    #expect(!gate.shouldChange(wanted: false, active: true))
    // Turning it on again is still allowed, and asking again resets the latch.
    #expect(gate.shouldChange(wanted: true, active: false))
    gate.userChangedSettings()
    #expect(gate.shouldChange(wanted: false, active: true))
  }

  @Test func aSuccessfulChangeClearsTheLatch() {
    var gate = LidClosedGate()
    gate.finished(turningOn: false, succeeded: false)
    gate.finished(turningOn: false, succeeded: true)
    #expect(!gate.inFlight)
    #expect(gate.shouldChange(wanted: false, active: true))
  }
}
