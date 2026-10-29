// NotificationCenterHelper.swift
// Brim
//
// Thin wrapper around UNUserNotificationCenter for the handful of local
// notifications Brim posts (e.g. "Screenshot saved", "Link copied"). macOS shows them
// under the Brim name and icon from the bundle; titles and bodies are looked up in
// Localizable.strings so they follow the app language.
//
// UNUserNotificationCenter requires a proper app bundle with a bundle
// identifier; when running as a bare `swift run` executable (no bundle),
// touching it can crash or silently misbehave, so every entry point here
// guards on `Bundle.main.bundleIdentifier != nil` and no-ops otherwise.

import Foundation
import UserNotifications

enum NotificationCenterHelper {

    /// Requests permission to display alert/sound/badge notifications.
    /// Safe to call unconditionally on launch; respects
    /// `AppSettings.shared.showNotifications` being toggled off later (the
    /// permission is requested once regardless, but `notify` checks the
    /// setting before posting).
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error {
                // No UI-facing surface for this yet; log for now.
                NSLog("Brim: notification authorization error: \(error.localizedDescription)")
            } else {
                NSLog("Brim: notification authorization granted: \(granted)")
            }
        }
    }

    /// Posts a local banner notification with `title` / `body`, provided the
    /// user has notifications enabled in AppSettings and has authorized them
    /// at the OS level. Fails silently (no-op) otherwise — notifications are
    /// a nice-to-have, never a blocking requirement.
    static func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        guard AppSettings.shared.showNotifications else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = L10n.tr(title)
            content.body = L10n.tr(body)
            content.sound = AppSettings.shared.playSound ? .default : nil

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error {
                    NSLog("Brim: failed to post notification: \(error.localizedDescription)")
                }
            }
        }
    }
}
