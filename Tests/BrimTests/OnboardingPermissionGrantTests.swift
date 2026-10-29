import EventKit
import Testing

@testable import Brim

/// macOS lists an app in a privacy pane only after it asked once, so "Grant" must ask first.
struct OnboardingPermissionGrantTests {
  @Test func firstPressAsksForPermissionsMacOSListsOnlyAfterAsking() {
    #expect(PermissionGrantStep.next(for: .screenRecording, state: .notGranted, alreadyAsked: false) == .prompt)
    #expect(PermissionGrantStep.next(for: .calendar, state: .unknown, alreadyAsked: false) == .prompt)
    #expect(PermissionGrantStep.next(for: .automation, state: .unknown, alreadyAsked: false) == .prompt)
    #expect(PermissionGrantStep.next(for: .notifications, state: .unknown, alreadyAsked: false) == .prompt)
  }

  @Test func refusedOrAlreadyAskedOpensSystemSettings() {
    #expect(PermissionGrantStep.next(for: .screenRecording, state: .notGranted, alreadyAsked: true) == .openSettings)
    #expect(PermissionGrantStep.next(for: .calendar, state: .notGranted, alreadyAsked: false) == .openSettings)
    #expect(PermissionGrantStep.next(for: .automation, state: .unknown, alreadyAsked: true) == .openSettings)
  }

  @Test func aCalendarNeverAskedIsNotShownAsRefused() {
    #expect(PermissionsModel.calendarState(.notDetermined) == .unknown)
    #expect(PermissionsModel.calendarState(.denied) == .notGranted)
    #expect(PermissionsModel.calendarState(.fullAccess) == .granted)
  }
}
