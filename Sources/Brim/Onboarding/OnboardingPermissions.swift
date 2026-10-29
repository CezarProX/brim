import AppKit
import ApplicationServices
import CoreServices
import EventKit
import UserNotifications

enum PermissionKind: String, CaseIterable, Identifiable {
  case accessibility, screenRecording, calendar, notifications, automation
  var id: String { rawValue }

  var title: String {
    switch self {
    case .accessibility: "Accessibility"
    case .screenRecording: "Screen Recording"
    case .calendar: "Calendar"
    case .notifications: "Notifications"
    case .automation: "Automation"
    }
  }

  var reason: String {
    switch self {
    case .accessibility: "Timers, meeting controls and window details"
    case .screenRecording: "Screenshots and screen capture"
    case .calendar: "Your next event and countdowns"
    case .notifications: "Capture confirmations and alerts"
    case .automation: "Dark Mode tile, Music and Spotify"
    }
  }

  var symbol: String {
    switch self {
    case .accessibility: "accessibility"
    case .screenRecording: "record.circle"
    case .calendar: "calendar"
    case .notifications: "bell.badge.fill"
    case .automation: "gearshape.2.fill"
    }
  }

  /// The System Settings pane where the user grants it.
  var settingsURL: URL {
    let base = "x-apple.systempreferences:"
    switch self {
    case .accessibility: return URL(string: base + "com.apple.preference.security?Privacy_Accessibility")!
    case .screenRecording: return URL(string: base + "com.apple.preference.security?Privacy_ScreenCapture")!
    case .calendar: return URL(string: base + "com.apple.preference.security?Privacy_Calendars")!
    case .notifications: return URL(string: base + "com.apple.Notifications-Settings.extension")!
    case .automation: return URL(string: base + "com.apple.preference.security?Privacy_Automation")!
    }
  }
}

enum PermissionState: Equatable {
  case granted, notGranted, unknown

  /// Maps the result of `AEDeterminePermissionToAutomateTarget`: noErr means allowed, -1743 denied;
  /// anything else (consent not asked yet, target not running) is unknown rather than a guess.
  static func fromAutomation(status: Int) -> PermissionState {
    switch status {
    case 0: .granted
    case -1743: .notGranted
    default: .unknown
    }
  }

  static func fromNotification(_ status: UNAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorized, .provisional, .ephemeral: .granted
    case .denied: .notGranted
    default: .unknown
    }
  }
}

/// What "Grant" does. macOS lists an app under Screen Recording, Calendars or Automation only after
/// it has asked once, so the first press asks; later presses (or a refusal) open System Settings.
enum PermissionGrantStep: Equatable {
  case prompt, openSettings

  static func next(for kind: PermissionKind, state: PermissionState, alreadyAsked: Bool) -> PermissionGrantStep {
    switch kind {
    case .accessibility: return .prompt
    case .screenRecording: return alreadyAsked ? .openSettings : .prompt
    case .calendar, .notifications, .automation:
      return state == .notGranted || alreadyAsked ? .openSettings : .prompt
    }
  }
}

/// Reads each permission's current state without prompting; `grant` asks.
@MainActor
final class PermissionsModel: ObservableObject {
  @Published private(set) var states: [PermissionKind: PermissionState] = [:]
  /// Asked during this tour. Screen Recording only reports a grant after Brim relaunches.
  @Published private(set) var asked: Set<PermissionKind> = []

  func refresh() {
    var next = states
    next[.accessibility] = AXIsProcessTrusted() ? .granted : .notGranted
    next[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    next[.calendar] = Self.calendarState(EKEventStore.authorizationStatus(for: .event))
    next[.automation] = Self.automationState()
    states = next
    // UserNotifications traps outside an app bundle (tests, `swift run`).
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    Task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      states[.notifications] = PermissionState.fromNotification(settings.authorizationStatus)
    }
  }

  func state(_ kind: PermissionKind) -> PermissionState { states[kind] ?? .unknown }

  func grant(_ kind: PermissionKind) {
    let step = PermissionGrantStep.next(for: kind, state: state(kind), alreadyAsked: asked.contains(kind))
    asked.insert(kind)
    guard step == .prompt else {
      NSWorkspace.shared.open(kind.settingsURL)
      return
    }
    switch kind {
    case .accessibility:
      _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      NSWorkspace.shared.open(kind.settingsURL)
    case .screenRecording:
      // Shows the system prompt and adds Brim to the Screen Recording list.
      if CGRequestScreenCaptureAccess() { refresh() }
    case .calendar:
      Task {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        refresh()
      }
    case .notifications:
      Task {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        refresh()
      }
    case .automation:
      Task {
        await Self.askForAutomation()
        refresh()
      }
    }
  }

  nonisolated static func calendarState(_ status: EKAuthorizationStatus) -> PermissionState {
    switch status {
    case .fullAccess: .granted
    case .notDetermined: .unknown
    default: .notGranted
    }
  }

  /// Asks to control System Events (it is launched hidden first: macOS only asks about a running app).
  private static func askForAutomation() async {
    let id = "com.apple.systemevents"
    if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    await Task.detached(priority: .userInitiated) {
      var address = AEAddressDesc()
      let created = id.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &address) }
      guard created == noErr else { return }
      defer { AEDisposeDesc(&address) }
      _ = AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, true)
    }.value
  }

  /// System Events is the app the Dark Mode tile talks to.
  private static func automationState() -> PermissionState {
    var address = AEAddressDesc()
    let id = "com.apple.systemevents"
    let created = id.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &address) }
    guard created == noErr else { return .unknown }
    defer { AEDisposeDesc(&address) }
    let status = AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, false)
    return PermissionState.fromAutomation(status: Int(status))
  }
}
