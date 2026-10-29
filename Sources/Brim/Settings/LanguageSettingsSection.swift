// LanguageSettingsSection.swift
// Brim
//
// Settings > General > Language: System, English or Română. The choice is written to `AppleLanguages`
// for this app and takes effect after a relaunch, which the section offers right away.

import AppKit
import SwiftUI

struct LanguageSettingsSection: View {
  @State private var language = AppSettings.shared.appLanguage
  @State private var needsRelaunch = false

  var body: some View {
    Section {
      Picker("Language", selection: $language) {
        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
      }
      .onChange(of: language) { _, value in
        AppSettings.shared.appLanguage = value
        needsRelaunch = true
      }
      if needsRelaunch {
        SettingsButtonRow(
          "Restart required", subtitle: "The new language applies after Brim restarts.", button: "Restart now"
        ) { AppRelauncher.relaunch() }
      }
    }
  }
}

/// Starts a fresh copy of the running app bundle, then quits this one.
@MainActor
enum AppRelauncher {
  static func relaunch() {
    let path = Bundle.main.bundleURL.path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"$0\"", path]
    do { try task.run() } catch { return }
    NSApp.terminate(nil)
  }
}
