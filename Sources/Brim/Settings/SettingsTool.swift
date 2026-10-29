// SettingsTool.swift
// Brim
//
// Every widget and tool in the island has one findable place: a row in Home & Widgets that opens
// its own short page, like System Settings' drill-in rows. Search finds them by name and keyword.

import SwiftUI

enum SettingsTool: String, CaseIterable, Identifiable, Hashable, Sendable {
  // Widgets: things that live on Home or the Widgets grid.
  case weather, stats, calendar, pomodoro, notes, agents, audioControl
  // Tools: droplets that run from a shortcut, the Ring or the grid.
  case actionRing, launcher, emoji, textCapture, dropClip, termiNotch, teleprompter, xcodeBuilds
  case stayAwake, localSend, cleaner, menuBarManager, mcp, finderServices

  var id: String { rawValue }

  static let widgets: [SettingsTool] = [.weather, .stats, .calendar, .pomodoro, .notes, .agents, .audioControl]
  static let tools: [SettingsTool] = allCases.filter { !widgets.contains($0) }

  var title: String {
    switch self {
    case .weather: "Weather"
    case .stats: "System Stats"
    case .calendar: "Calendar"
    case .pomodoro: "Pomodoro"
    case .notes: "Notes"
    case .agents: "Agents & Meetings"
    case .audioControl: "Audio Control"
    case .actionRing: "Action Ring"
    case .launcher: "Launcher"
    case .emoji: "Emoji Picker"
    case .textCapture: "Text Capture"
    case .dropClip: "DropClip"
    case .termiNotch: "Termi-Notch"
    case .teleprompter: "Teleprompter"
    case .xcodeBuilds: "Xcode Builds"
    case .stayAwake: "Stay Awake"
    case .localSend: "LocalSend"
    case .cleaner: "Cleaner"
    case .menuBarManager: "Menu Bar Manager"
    case .mcp: "MCP Server"
    case .finderServices: "Finder Services"
    }
  }

  /// One line under the title, in the list and on the tool's page.
  var summary: String {
    switch self {
    case .weather: "Your city, units and how often it refreshes."
    case .stats: "CPU, memory and disk cards, and alerts."
    case .calendar: "Week layout, Google accounts and Things 3."
    case .pomodoro: "Session color, sounds and auto-start."
    case .notes: "Apple Notes sync and your Obsidian vault."
    case .agents: "Claude Code, Codex and meeting controls."
    case .audioControl: "Per-app volume and preferred devices."
    case .actionRing: "A ring of actions at the pointer."
    case .launcher: "Search apps, files and snippets."
    case .emoji: "Pick emoji from anywhere."
    case .textCapture: "Copy text and QR codes from the screen."
    case .dropClip: "Quick actions for selected text."
    case .termiNotch: "A terminal in the notch."
    case .teleprompter: "A script that scrolls under the camera."
    case .xcodeBuilds: "Build progress and results in the island."
    case .stayAwake: "Keep your Mac awake on a schedule."
    case .localSend: "Send files to nearby devices."
    case .cleaner: "Uninstall apps with their leftovers."
    case .menuBarManager: "Hide menu bar icons you rarely use."
    case .mcp: "Let AI apps use Brim’s tools."
    case .finderServices: "Brim actions in Finder’s menus."
    }
  }

  /// Search words besides the title.
  var keywords: [String] {
    switch self {
    case .weather: ["city", "temperature", "forecast", "location", "celsius", "fahrenheit"]
    case .stats: ["cpu", "memory", "ram", "disk", "gpu", "network", "alerts", "sample interval"]
    case .calendar: ["week starts", "week numbers", "google calendar", "google tasks", "reminders", "things", "to-dos"]
    case .pomodoro: ["focus", "timer", "session color", "end sound", "ambient sound", "auto start"]
    case .notes: ["apple notes", "obsidian", "vault", "markdown"]
    case .agents: ["claude", "codex", "cursor", "opencode", "ai", "usage", "meeting", "mute", "zoom", "teams", "meet"]
    case .audioControl: ["per-app volume", "app volume", "boost", "volume curve", "preferred devices", "outputs", "microphones"]
    case .actionRing: ["ring", "slots", "pointer"]
    case .launcher: ["thunderstorm", "spotlight", "calculator", "quicklinks", "snippets"]
    case .emoji: ["emoji", "skin tone"]
    case .textCapture: ["ocr", "qr code", "barcode", "scan"]
    case .dropClip: ["selected text", "translate", "search"]
    case .termiNotch: ["terminal", "shell"]
    case .teleprompter: ["script", "mirror", "prompter"]
    case .xcodeBuilds: ["xcode", "build"]
    case .stayAwake: ["caffeine", "keep awake", "schedule", "lid closed", "sleep"]
    case .localSend: ["send files", "nearby devices", "airdrop"]
    case .cleaner: ["uninstall", "leftovers", "cache cleanup"]
    case .menuBarManager: ["hidden bar", "thaw", "hide menu bar icons"]
    case .mcp: ["ai apps", "claude desktop", "server"]
    case .finderServices: ["quick actions", "services", "right-click"]
    }
  }

  /// The header its settings section already uses, hidden on the tool's own page.
  var sectionTitle: String {
    switch self {
    case .launcher: "Thunderstorm launcher"
    case .agents: "Agents"
    case .mcp: "MCP"
    default: title
    }
  }

  var icon: FeatureIcon {
    switch self {
    case .weather: IslandWidgetTile.weather.icon
    case .stats: IslandWidgetTile.stats.icon
    case .calendar: IslandWidgetTile.calendar.icon
    case .pomodoro: IslandWidgetTile.timer.icon
    case .notes: IslandWidgetTile.notes.icon
    case .agents: IslandWidgetTile.agents.icon
    case .audioControl: IslandWidgetTile.audioControl.icon
    case .actionRing: .custom(IconArt.actionRing)
    case .launcher: IslandWidgetTile.launcher.icon
    case .emoji: IslandWidgetTile.emojiPicker.icon
    case .textCapture: IslandWidgetTile.textCapture.icon
    case .dropClip: IslandWidgetTile.dropClip.icon
    case .termiNotch: IslandWidgetTile.termiNotch.icon
    case .teleprompter: IslandWidgetTile.teleprompter.icon
    case .xcodeBuilds: IslandWidgetTile.xcodeBuilds.icon
    case .stayAwake: IslandWidgetTile.keepAwake.icon
    case .localSend: IslandWidgetTile.share.icon
    case .cleaner: IslandWidgetTile.cleaner.icon
    case .menuBarManager: IslandWidgetTile.menuBarManager.icon
    case .mcp: .custom(IconArt.mcp)
    case .finderServices: .real(.app("/System/Library/CoreServices/Finder.app"), fallback: IconArt.folder)
    }
  }

  /// The tool's settings, as grouped-form sections.
  @MainActor @ViewBuilder var sections: some View {
    switch self {
    case .weather: WidgetsSettingsSection(parts: [.weather])
    case .stats: WidgetsSettingsSection(parts: [.stats])
    case .calendar: ProductivitySettingsSection(parts: [.calendar])
    case .pomodoro: ProductivitySettingsSection(parts: [.pomodoro])
    case .notes: ProductivitySettingsSection(parts: [.notes])
    case .agents: AgentsSettingsSection(); MeetingsSettingsSection()
    case .audioControl: AudioControlSettingsSection()
    case .actionRing: RingSettingsSection()
    case .launcher: ThunderstormSettingsSection()
    case .emoji: EmojiSettingsSection()
    case .textCapture: TextCaptureSettingsSection()
    case .dropClip: DropClipSettingsSection()
    case .termiNotch: TermiNotchSettingsSection()
    case .teleprompter: TeleprompterSettingsSection()
    case .xcodeBuilds: XcodeBuildsSettingsSection()
    case .stayAwake: StayAwakeSettingsSection()
    case .localSend: LocalSendSettingsSection()
    case .cleaner: CleanerSettingsSection()
    case .menuBarManager: MenuBarManagerSettingsSection()
    case .mcp: MCPSettingsSection()
    case .finderServices: FinderServicesSettingsSection()
    }
  }
}

/// The widget and tool rows on the Home & Widgets page; each opens the tool's own page.
struct SettingsToolLibrary: View {
  var body: some View {
    Section {
      ForEach(SettingsTool.widgets) { row($0) }
    } header: {
      Text("Widgets")
    }
    Section {
      ForEach(SettingsTool.tools) { row($0) }
    } header: {
      Text("Tools")
    } footer: {
      SettingsFootnote("Open a widget or tool to change only its settings.")
    }
  }

  private func row(_ tool: SettingsTool) -> some View {
    NavigationLink(value: tool) {
      Label {
        Text(LocalizedStringKey(tool.title))
        Text(LocalizedStringKey(tool.summary))
      } icon: {
        FeatureIconView(tool.icon, size: 24)
      }
    }
    .settingsAnchor("tool.\(tool.rawValue)")
  }
}

/// A tool's own page: its icon, name and summary, then its settings.
struct SettingsToolPage: View {
  let tool: SettingsTool

  var body: some View {
    SettingsScrollingForm {
      Section {
        VStack(spacing: 6) {
          FeatureIconView(tool.icon, size: 56).padding(.bottom, 4)
          Text(LocalizedStringKey(tool.title)).font(.title3.weight(.semibold))
          Text(LocalizedStringKey(tool.summary))
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
      }
      tool.sections
    }
    .environment(\.settingsRedundantTitle, tool.sectionTitle)
    .navigationTitle(LocalizedStringKey(tool.title))
  }
}
