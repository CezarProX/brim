// ProductivitySettingsSection.swift
// Brim
//
// Settings for the Calendar, Pomodoro, Notes, Obsidian and Things surfaces.

import SwiftUI

struct ProductivitySettingsSection: View {
  /// Which groups to show; the Widgets library opens one tool at a time.
  enum Part: CaseIterable { case calendar, pomodoro, notes }
  var parts: Set<Part> = Set(Part.allCases)

  @State private var weekStart = AppSettings.shared.calendarWeekStart
  @State private var weekNumbers = AppSettings.shared.calendarWeekNumbers
  @State private var things = AppSettings.shared.thingsBridgeEnabled
  @State private var appleNotes = AppSettings.shared.appleNotesSyncEnabled
  @ObservedObject private var obsidian = ObsidianModel.shared
  @State private var focusHint = AppSettings.shared.pomodoroFocusModeHint
  @State private var autoStart = AppSettings.shared.pomodoroAutoStart
  @State private var endSound = PomodoroEndSound.current
  @State private var ambient = AmbientSound.current
  @State private var color = SessionColor.current

  private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

  var body: some View {
    Group {
      if parts.contains(.calendar) { calendarGroups }
      if parts.contains(.pomodoro) { pomodoroGroup }
      if parts.contains(.notes) { notesGroup }
    }
  }

  @ViewBuilder private var calendarGroups: some View {
      group("Calendar") {
        Picker("Week starts on", selection: $weekStart) {
          Text("System default").tag(0)
          ForEach(1...7, id: \.self) { Text(Self.days[$0 - 1]).tag($0) }
        }
        .onChange(of: weekStart) { _, value in
          AppSettings.shared.calendarWeekStart = value
          CalendarSettingsTick.shared.bump()
        }
        Toggle("Show week numbers", isOn: $weekNumbers)
          .onChange(of: weekNumbers) { _, value in
            AppSettings.shared.calendarWeekNumbers = value
            CalendarSettingsTick.shared.bump()
          }
        note("Google Calendar and Google Tasks appear here when your Google account is added in System Settings → Internet Accounts with Calendars and Reminders on. Brim reads them through macOS; it never sees your Google password.")
      }
      group("Things 3") {
        Toggle("Show Things 3 “Today” to-dos in the Calendar", isOn: $things)
          .disabled(!ThingsModel.shared.isInstalled)
          .onChange(of: things) { _, value in AppSettings.shared.thingsBridgeEnabled = value }
        note(ThingsModel.shared.isInstalled
          ? "Reads your Today list and can mark to-dos done. macOS will ask once to let Brim control Things. Nothing leaves your Mac."
          : "Things 3 isn’t installed on this Mac.")
      }
  }

  private var pomodoroGroup: some View {
      group("Pomodoro") {
        Picker("Session color", selection: $color) { ForEach(SessionColor.allCases) { Text($0.rawValue.capitalized).tag($0) } }
          .onChange(of: color) { _, value in AppSettings.shared.pomodoroColorName = value.rawValue }
        Picker("End sound", selection: $endSound) { ForEach(PomodoroEndSound.allCases) { Text($0.title).tag($0) } }
          .onChange(of: endSound) { _, value in AppSettings.shared.pomodoroEndSoundName = value.rawValue }
        Picker("Ambient sound", selection: $ambient) { ForEach(AmbientSound.allCases) { Text($0.title).tag($0) } }
          .onChange(of: ambient) { _, value in AppSettings.shared.pomodoroAmbientName = value.rawValue }
        Toggle("Start the next focus or break automatically", isOn: $autoStart)
          .onChange(of: autoStart) { _, value in AppSettings.shared.pomodoroAutoStart = value }
        Toggle("Remind me to turn on a Focus mode", isOn: $focusHint)
          .onChange(of: focusHint) { _, value in AppSettings.shared.pomodoroFocusModeHint = value }
        note("Ambient sound is generated on this Mac while a focus session runs. macOS doesn’t let apps switch Focus modes, so this only shows a reminder.")
      }
  }

  private var notesGroup: some View {
      group("Notes") {
        Toggle("Sync with Apple Notes (“Brim” folder)", isOn: $appleNotes)
          .onChange(of: appleNotes) { _, value in AppSettings.shared.appleNotesSyncEnabled = value }
        note("Best effort and two-way: the newest edit wins and nothing is ever deleted. macOS asks once to let Brim control Notes.")
        LabeledContent {
          HStack {
            if !obsidian.followsObsidian, !obsidian.knownVaults.isEmpty {
              Button("Follow Obsidian") { obsidian.followObsidian() }
            }
            Button("Choose folder…") { obsidian.chooseVault() }
          }
        } label: {
          Text("Obsidian")
          Text(obsidianStatus)
        }
        .settingsAnchor("notes.obsidian")
        note("Brim connects to the vault you have open in Obsidian automatically and follows it when you switch. Pick a folder to pin one instead. Notes are edited as .md files directly; Obsidian does not need to be running.")
      }
  }

  private var obsidianStatus: String {
    guard let vault = obsidian.vault else { return "No Obsidian vault found" }
    return obsidian.followsObsidian ? "Obsidian vault: \(vault.name) (linked to Obsidian)" : "Obsidian vault: \(vault.name)"
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }
}
