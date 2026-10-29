// NotificationHUDSettingsSection.swift
// Brim
//
// Settings for mirroring macOS notifications into the island. Self-contained; the integrator
// embeds it in the island settings page.

import SwiftUI

struct NotificationHUDSettingsSection: View {
  @State private var enabled = AppSettings.shared.notificationHUDEnabled
  @State private var hideBanner = AppSettings.shared.notificationHUDHideBanner
  @State private var fallback = AppSettings.shared.notificationHUDUsernotedFallback
  @State private var showBody = AppSettings.shared.notificationHUDShowBody
  @State private var hideWhileSharing = AppSettings.shared.notificationHUDHideWhileSharing
  @State private var duration = AppSettings.shared.notificationHUDDuration
  @State private var denied = AppSettings.shared.notificationHUDDeniedApps.joined(separator: ", ")
  @State private var allowed = AppSettings.shared.notificationHUDAllowedApps.joined(separator: ", ")

  @ViewBuilder var body: some View {
    SettingsSection {
      Toggle(isOn: $enabled) {
        Text("Show notifications in the island")
        Text("Off by default. Brim reads each macOS banner as it appears using Accessibility (System Settings > Privacy & Security > Accessibility). Everything stays on this Mac.")
      }
      .onChange(of: enabled) { _, value in commit { $0.notificationHUDEnabled = value } }

      Group {
        Toggle("Hide the macOS banner after capturing it", isOn: $hideBanner)
          .onChange(of: hideBanner) { _, value in commit { $0.notificationHUDHideBanner = value } }
        Toggle("Show message previews", isOn: $showBody)
          .onChange(of: showBody) { _, value in commit { $0.notificationHUDShowBody = value } }
        Toggle("Hide while screen sharing", isOn: $hideWhileSharing)
          .onChange(of: hideWhileSharing) { _, value in commit { $0.notificationHUDHideWhileSharing = value } }
        Stepper("Stay for \(Int(duration)) seconds", value: $duration, in: 2...20)
          .onChange(of: duration) { _, value in commit { $0.notificationHUDDuration = value } }
        Toggle(isOn: $fallback) {
          Text("Read the notification database instead (Full Disk Access)")
          Text("Alternative that works without Accessibility: it needs Full Disk Access and shows notifications about two seconds late. Messages replies need Automation access to Messages.")
        }
        .onChange(of: fallback) { _, value in commit { $0.notificationHUDUsernotedFallback = value } }
        appList("Only these apps (names or bundle ids, comma separated; empty = all)", text: $allowed) { list in
          commit { $0.notificationHUDAllowedApps = list }
        }
        appList("Never show these apps", text: $denied) { list in
          commit { $0.notificationHUDDeniedApps = list }
        }
      }
      .disabled(!enabled)
    }
    ReplyConnectionsSettingsSection()
      .disabled(!enabled)
  }

  private func appList(_ title: String, text: Binding<String>, save: @escaping ([String]) -> Void) -> some View {
    TextField(LocalizedStringKey(title), text: text, prompt: Text("e.g. Slack, com.apple.mail"))
      .onSubmit { save(Self.parse(text.wrappedValue)) }
  }

  static func parse(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  private func commit(_ change: (AppSettings) -> Void) {
    change(AppSettings.shared)
    Task { @MainActor in NotificationHUDModel.shared.start() }
  }
}
