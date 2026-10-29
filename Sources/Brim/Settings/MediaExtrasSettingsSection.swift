// MediaExtrasSettingsSection.swift
// Brim
//
// Media extras: privacy filters, Automix, quality badge, Discord Rich Presence, interaction options.

import SwiftUI

struct MediaExtrasSettingsSection: View {
  @State private var hidePrivate = AppSettings.shared.mediaHidePrivateBrowsing
  @State private var allowed = Set(AppSettings.shared.mediaAllowedSources)
  @State private var automix = AppSettings.shared.mediaAutomixIndicator
  @State private var badge = AppSettings.shared.mediaQualityBadge
  @State private var discord = AppSettings.shared.discordPresenceEnabled
  @State private var clientID = AppSettings.shared.discordClientID
  @State private var hideMinutes = AppSettings.shared.mediaHideOnPauseMinutes
  @State private var spacebar = AppSettings.shared.mediaSpacebarPlayPause
  @State private var click = AppSettings.shared.notchMusicClickAction

  private let minuteOptions = [1, 2, 5, 10, 30, 0]
  private static let knownSources: [(String, String)] = NowPlayingSource.allCases.reduce(into: []) { result, source in
    if !result.contains(where: { $0.0 == source.bundleID }) { result.append((source.bundleID, source.name)) }
  }

  var body: some View {
    Group {
      group("Privacy") {
        Toggle(isOn: $hidePrivate) {
          Text("Hide media from Incognito / Private windows")
          Text("Chrome-family browsers are checked through Automation; others through window titles when Accessibility is allowed. If a window can't be inspected, the media is shown.")
        }
        .onChange(of: hidePrivate) { _, value in AppSettings.shared.mediaHidePrivateBrowsing = value }
      }
      SettingsSection(
        "Filter media sources", footer: "Only checked sources appear in the island. Leave all checked to allow everything."
      ) {
        ForEach(Self.knownSources, id: \.0) { bundle, name in
          Toggle(name, isOn: Binding(
            get: { allowed.isEmpty || allowed.contains(bundle) },
            set: { toggle(bundle, $0) }))
        }
      }
      group("Apple Music") {
        Toggle("Automix indicator (interlocked rings)", isOn: $automix)
          .onChange(of: automix) { _, value in AppSettings.shared.mediaAutomixIndicator = value }
        Toggle("Lossless / Hi-Res / Dolby Atmos badge", isOn: $badge)
          .onChange(of: badge) { _, value in AppSettings.shared.mediaQualityBadge = value }
        note("Both are best effort: they follow Music's Crossfade setting and the format Music reports for the playing track.")
      }
      group("Island behavior") {
        Picker("Hide a paused song after", selection: $hideMinutes) {
            ForEach(minuteOptions, id: \.self) { Text($0 == 0 ? "Never" : "\($0) min").tag($0) }
          }
        .onChange(of: hideMinutes) { _, value in AppSettings.shared.mediaHideOnPauseMinutes = value }
        Toggle("Space bar plays / pauses while the island is open", isOn: $spacebar)
          .onChange(of: spacebar) { _, value in AppSettings.shared.mediaSpacebarPlayPause = value }
        Picker("Clicking the notch while music plays", selection: $click) {
            ForEach(NotchMusicClickAction.allCases) { Text($0.title).tag($0) }
          }
        .onChange(of: click) { _, value in AppSettings.shared.notchMusicClickAction = value }
      }
      group("Discord Rich Presence") {
        Toggle("Show what I'm listening to on Discord", isOn: $discord)
          .settingsAnchor("media.discord")
          .onChange(of: discord) { _, value in
            AppSettings.shared.discordPresenceEnabled = value
            MediaServices.shared.sync()
          }
        TextField("Discord application ID", text: $clientID)
          .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
          .onChange(of: clientID) { _, value in
            AppSettings.shared.discordClientID = value
            MediaServices.shared.sync()
          }
        if !clientID.isEmpty, !DiscordIPCProtocol.isValidClientID(clientID.trimmingCharacters(in: .whitespaces)) {
          Text("That doesn't look like an application ID (15 to 22 digits).").font(.caption).foregroundStyle(.red)
        }
        note("Off by default. Create an application at discord.com/developers and paste its Application ID. The song and artist go only to your own Discord app on this Mac, which shows them on your profile.")
      }
    }
  }

  private func toggle(_ bundle: String, _ on: Bool) {
    var next = allowed.isEmpty ? Set(Self.knownSources.map(\.0)) : allowed
    if on { next.insert(bundle) } else { next.remove(bundle) }
    if next.count == Self.knownSources.count || next.isEmpty { next = [] }
    allowed = next
    AppSettings.shared.mediaAllowedSources = Array(next)
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }
}
