// SettingsRootView.swift
// Brim
//
// System Settings' layout: a translucent sidebar (search field, then a short list of pages with
// their real icons) beside the selected page, which is a grouped Form under a picture of what it
// controls. Home & Widgets drills into one page per widget or tool; rare options sit under each
// page's Advanced row.

import SwiftUI

struct SettingsRootView: View {
  @ObservedObject private var navigator: SettingsNavigator
  @State private var searchQuery = ""

  init() { self.init(navigator: .shared) }

  init(initialPane: SettingsPane) { self.init(navigator: SettingsNavigator(SettingsDestination(initialPane))) }

  init(destination: SettingsDestination) { self.init(navigator: SettingsNavigator(destination)) }

  init(navigator: SettingsNavigator) {
    _navigator = ObservedObject(wrappedValue: navigator)
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 260)
    } detail: {
      NavigationStack(path: $navigator.toolPath) {
        SettingsPaneContent(pane: navigator.pane)
          .id(navigator.pane)
          .navigationTitle(LocalizedStringKey(navigator.pane.rawValue))
          .navigationDestination(for: SettingsTool.self) { SettingsToolPage(tool: $0) }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .background { GlassWindowBackdrop().ignoresSafeArea() }
    .environmentObject(navigator)
    .frame(minWidth: SettingsWindowLayout.minimumSize.width, minHeight: SettingsWindowLayout.minimumSize.height)
  }

  // MARK: Sidebar

  private var sidebar: some View {
    ScrollViewReader { proxy in
      List(selection: paneSelection) {
        ForEach(SettingsPaneGroup.allCases) { group in
          let panes = visiblePanes.filter { $0.group == group }
          if !panes.isEmpty {
            Section {
              ForEach(panes) { SettingsSidebarRow(pane: $0).tag($0).id($0) }
            }
          }
        }
        // Searching also lists the matching widgets and tools, which live inside Home & Widgets.
        if !searchQuery.isEmpty, !matchingTools.isEmpty {
          Section {
            ForEach(matchingTools) { tool in
              Button { navigator.open(.tool(tool)) } label: {
                Label {
                  Text(LocalizedStringKey(tool.title)).lineLimit(1)
                } icon: {
                  FeatureIconView(tool.icon, size: 20)
                }
              }
              .buttonStyle(.plain)
            }
          } header: {
            Text("Widgets & Tools")
          }
        }
      }
      .listStyle(.sidebar)
      .searchable(text: $searchQuery, placement: .sidebar, prompt: Text("Search"))
      // Opening straight onto a lower page (e.g. from a deep link) keeps its row in view.
      .onAppear {
        let pane = navigator.pane
        DispatchQueue.main.async { proxy.scrollTo(pane, anchor: .center) }
      }
    }
  }

  private var paneSelection: Binding<SettingsPane?> {
    Binding(get: { navigator.pane }, set: { if let pane = $0 { navigator.select(pane) } })
  }

  private var visiblePanes: [SettingsPane] {
    let titles = SettingsSearchLexicon.matches(searchQuery, in: SettingsPane.allCases.map(\.rawValue))
    return SettingsPane.allCases.filter { titles.contains($0.rawValue) }
  }

  private var matchingTools: [SettingsTool] { SettingsSearchLexicon.matchingTools(searchQuery) }
}

/// Window sizes shared by the window controller and the render tests.
enum SettingsWindowLayout {
  static let defaultSize = CGSize(width: 860, height: 640)
  static let minimumSize = CGSize(width: 760, height: 520)
}

/// One sidebar row: the page's 20-point icon and its name, as in System Settings.
struct SettingsSidebarRow: View {
  let pane: SettingsPane

  var body: some View {
    Label {
      Text(LocalizedStringKey(pane.rawValue)).lineLimit(1)
    } icon: {
      FeatureIconView(pane.icon, size: 20)
    }
  }
}

/// The selected page: a grouped Form under its header, the rare options under Advanced.
struct SettingsPaneContent: View {
  let pane: SettingsPane

  var body: some View {
    SettingsPage(pane: pane) { sections }
  }

  @ViewBuilder
  private var sections: some View {
    switch pane {
    case .general:
      GeneralSettingsView()
      SettingsAdvancedSections(anchors: ["menubar.commandCenter"]) { MenuBarSettingsSection() }
    case .capture:
      CaptureSettingsSections()
      SavingSettingsView()
      SettingsAdvancedSections(anchors: ["upload.service"]) { UploadSettingsView() }
    case .shortcut:
      ShortcutSettingsView()
    case .island:
      ShellSettingsSection(part: .basic)
      ThemingSettingsSection(part: .basic)
      SettingsAdvancedSections(anchors: ["island.displays"]) {
        ShellSettingsSection(part: .advanced)
        ThemingSettingsSection(part: .advanced)
      }
    case .widgets:
      WidgetsSettingsSection(parts: [.home])
      SettingsToolLibrary()
    case .media:
      MediaSettingsSection()
      SettingsAdvancedSections(anchors: ["media.discord"]) {
        MediaExtrasSettingsSection()
        LiquidPlayerSettingsSection()
      }
    case .hud:
      IslandSettingsView()
      HUDSettingsSection()
      SettingsAdvancedSections {
        HUDExtrasSettingsSection()
        BluetoothDevicesSettingsSection()
      }
    case .notifications:
      NotificationHUDSettingsSection()
    case .lockScreen:
      LockScreenSettingsSection()
      SettingsAdvancedSections { LockScreenV2Section() }
    case .clipboard:
      ClipboardSettingsView()
      TransformSettingsSection(part: .basic)
      SettingsAdvancedSections { TransformSettingsSection(part: .advanced) }
    case .about:
      AboutSettingsView()
    }
  }
}

/// Sidebar groups, separated by space as in System Settings.
enum SettingsPaneGroup: String, CaseIterable, Identifiable {
  case brim, island, other

  var id: String { rawValue }
}

/// Every Settings page, in sidebar order. Raw values are the sidebar titles and the keys of
/// `SettingsSearchLexicon.keywords`.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
  case general = "General"
  case capture = "Capture & Recording"
  case shortcut = "Shortcuts"
  case island = "Island"
  case widgets = "Home & Widgets"
  case media = "Music"
  case hud = "HUDs & Live Activities"
  case notifications = "Notifications & Replies"
  case lockScreen = "Lock Screen"
  case clipboard = "Clipboard & Tray"
  case about = "About"

  var id: String { rawValue }

  var group: SettingsPaneGroup {
    switch self {
    case .general, .capture, .shortcut: .brim
    case .island, .widgets, .media, .hud, .notifications, .lockScreen, .clipboard: .island
    case .about: .other
    }
  }

  /// One line under the page's title in its header, like System Settings.
  var summary: String {
    switch self {
    case .general: "Turn the island on, take the tour, and choose how Brim starts."
    case .capture: "What happens after a capture, where it is saved and how it is shared."
    case .shortcut: "Keyboard shortcuts for capturing and recording from anywhere."
    case .island: "How the island opens, how it looks and how big it is."
    case .widgets: "Home widgets, glances beside the island, and every widget and tool."
    case .media: "Now Playing, lyrics, player buttons and the floating player."
    case .hud: "Volume and brightness pop-ups, and live flashes for charging, Caps Lock and more."
    case .notifications: "Show notifications from your apps in the island and reply from there."
    case .lockScreen: "The island and widgets on the Lock Screen."
    case .clipboard: "Clipboard history, pins and privacy, and the file tray."
    case .about: "Version, updates, backups and troubleshooting."
    }
  }
}
