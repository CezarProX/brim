// UpdatesSettingsSection.swift
// Brim

import SwiftUI

/// Where to look for new versions. Empty by default: Brim contacts nothing until you add a feed.
struct UpdatesSettingsSection: View {
  @State private var feed = AppSettings.shared.updateFeedURL
  @State private var auto = AppSettings.shared.updateAutoCheck

  private var feedIsValid: Bool { feed.isEmpty || UpdateFeed.validatedURL(feed) != nil }

  var body: some View {
    SettingsSection(
      "Updates",
      footer: "Optional. A JSON release file (version, notes, url), a GitHub releases API address or a Sparkle appcast. Nothing is contacted until you add one; Brim only tells you a new version exists and links to the download, it never installs anything itself."
    ) {
      TextField("Update feed", text: $feed, prompt: Text("https://example.com/brim/appcast.json"))
        .onSubmit(save)
        .onChange(of: feed) { _, _ in if feedIsValid { save() } }
      if !feedIsValid {
        Text("The address must start with https://").font(.caption).foregroundStyle(.orange)
      }
      Toggle("Check once a day in the background", isOn: $auto)
        .disabled(feed.isEmpty || !feedIsValid)
        .onChange(of: auto) { _, value in
          AppSettings.shared.updateAutoCheck = value
          UpdateChecker.shared.startAutoCheck()
        }
      LabeledContent {
        Button("Check for Updates") { UpdateChecker.shared.checkInteractively() }
      } label: {
        Text("Software update")
        if let last = AppSettings.shared.updateLastCheck {
          Text("Last checked \(last.formatted(.relative(presentation: .named)))")
        }
      }
    }
  }

  private func save() {
    guard feedIsValid else { return }
    AppSettings.shared.updateFeedURL = feed
    UpdateChecker.shared.startAutoCheck()
  }
}
