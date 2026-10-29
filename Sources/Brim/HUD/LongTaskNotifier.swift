import AppKit
import Foundation
import UserNotifications

/// "Notify me" when a long download, recording or transform finishes while Brim is in the
/// background. The permission is requested the first time the option is used, never at launch.
@MainActor
final class LongTaskNotifier {
    static let shared = LongTaskNotifier()

    /// Call when a task ends. Does nothing unless the setting is on, the task was long and the app is inactive.
    func finished(title: String, body: String, duration: TimeInterval) {
        guard LongTaskNotifyPolicy.shouldNotify(
            enabled: AppSettings.shared.notifyLongTasks, duration: duration, appIsActive: NSApp?.isActive ?? false)
        else { return }
        post(title: title, body: body)
    }

    /// Asks for permission when the user turns the option on.
    func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func post(title: String, body: String) {
        // UNUserNotificationCenter needs an app bundle; in tests and `swift run` it would trap.
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(120))
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
