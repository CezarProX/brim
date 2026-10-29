// ShellSettingsSection.swift
// Brim
//
// How the island opens, closes, hides, sizes and moves (General + Theming > Size).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShellSettingsSection: View {
  /// Bumped on every write so the view re-reads `AppSettings`, the single source of truth.
  @State private var revision = 0
  private let settings: AppSettings
  private let notifies: Bool
  /// nil shows every section; the Island page shows the basics and tucks the rest under Advanced.
  private let part: SettingsPart?

  init(settings: AppSettings = .shared, notifies: Bool = true, part: SettingsPart? = nil) {
    self.settings = settings
    self.notifies = notifies
    self.part = part
  }

  var body: some View {
    let _ = revision
    Group {
      if part != .advanced {
        openingSection
        ShellExtrasSettingsSection(settings: settings, notifies: notifies, part: .basic)
      }
      if part != .basic {
        gesturesSection
        ShellExtrasSettingsSection(settings: settings, notifies: notifies, part: .advanced)
        animationSection
        visibilitySection
        displaysSection
        sizeSection
      }
    }
  }

  // MARK: Sections

  private var openingSection: some View {
    SettingsSection(
      "Opening and closing",
      footer: settings.shellOpensOnHover
        ? "Clicking the closed notch also opens it."
        : "Hover-open is off: click the closed notch, or press ⌥⌘N. Click elsewhere to close."
    ) {
      Toggle("Open the notch when the pointer rests on it", isOn: binding(\.shellOpensOnHover))
      if settings.shellOpensOnHover {
        slider("Open delay", binding(\.shellOpenDelay), AppSettings.ShellRange.openDelay, step: 0.01) {
          $0 < 0.005 ? "Instant" : String(format: "%.2fs", $0)
        }
      }
      Toggle("Auto-collapse when the pointer leaves", isOn: binding(\.shellAutoCollapse))
      if settings.shellAutoCollapse {
        slider("Collapse delay", binding(\.shellCollapseDelay), AppSettings.ShellRange.collapseDelay, step: 0.01) {
          String(format: "%.2fs", $0)
        }
      }
      Toggle("Auto-expand for new recordings, timers and calls", isOn: binding(\.shellAutoExpandActivities))
    }
  }

  private var gesturesSection: some View {
    SettingsSection(
      "Gestures and shortcut",
      footer: "With two live activities, flick sideways on the closed notch to swap which one owns it. A hidden notch comes back with a right-click on its spot, ⌥⌘N, or after an hour."
    ) {
      Picker("Right-click the notch", selection: binding(\.shellRightClickAction)) {
        ForEach(ShellRightClickAction.allCases) { Text($0.title).tag($0) }
      }
      Toggle("Two-finger swipe switches pages", isOn: binding(\.shellSwipeNavigation))
      Toggle("Haptic feedback on open and file drop", isOn: binding(\.shellHaptics))
      Toggle("⌥⌘N toggles the island under the pointer", isOn: binding(\.shellToggleHotkeyEnabled))
    }
  }

  private var animationSection: some View {
    SettingsSection(
      "Animation speed", footer: "Scales every island spring. Reduce Motion in System Settings always wins."
    ) {
      Picker("Speed", selection: binding(\.shellAnimationSpeed)) {
        ForEach(ShellAnimationSpeed.allCases) { speed in
          Text("\(speed.title) \(Self.caption(for: speed))").tag(speed)
        }
      }
    }
  }

  private var visibilitySection: some View {
    section("Hide the island") {
      Toggle("In fullscreen apps", isOn: binding(\.shellHideOnFullscreen))
      Toggle("In Mission Control", isOn: binding(\.shellHideInMissionControl))
      Toggle("From screenshots and screen sharing", isOn: binding(\.shellHideFromCapture))
      hiddenApps
    }
  }

  private var displaysSection: some View {
    section("Displays without a notch") {
      Picker("Show on external displays", selection: binding(\.shellExternalVisibility)) {
        ForEach(ShellExternalVisibility.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented).fixedSize()
      .settingsAnchor("island.displays")
      HStack(spacing: 12) {
        ForEach(ShellDisplayStyle.allCases) { style in styleCard(style) }
      }
      .opacity(settings.shellExternalVisibility == .never ? 0.45 : 1)
    }
  }

  private var sizeSection: some View {
    Group {
      SettingsSection("Dynamic Island size") {
        points("Width", binding(\.shellIslandWidthOffset), AppSettings.ShellRange.islandWidth)
        points("Height", binding(\.shellIslandHeightOffset), AppSettings.ShellRange.islandHeight)
        points("Distance from top", binding(\.shellIslandVerticalOffset), AppSettings.ShellRange.islandPosition)
      }
      SettingsSection("Notch size") {
        points("Width", binding(\.shellNotchWidthOffset), AppSettings.ShellRange.notchWidth)
        points("Height", binding(\.shellNotchHeightOffset), AppSettings.ShellRange.notchHeight)
        LabeledContent("Island and notch sizes") {
          Button("Reset sizes", action: resetSizes).disabled(sizesAreDefault)
        }
      }
    }
  }

  // MARK: Pieces

  static func symbol(for speed: ShellAnimationSpeed) -> String {
    switch speed {
    case .turtle: "tortoise.fill"
    case .human: "figure.walk"
    case .cheetah: "hare.fill"
    case .falcon: "bolt.fill"
    }
  }

  static func caption(for speed: ShellAnimationSpeed) -> String {
    String(format: "%.2g×", 1 / speed.durationScale)
  }

  /// A tiny display with the island drawn the way that style will look.
  private func styleCard(_ style: ShellDisplayStyle) -> some View {
    let selected = settings.shellExternalStyle == style
    return Button { binding(\.shellExternalStyle).wrappedValue = style } label: {
      VStack(spacing: 8) {
        ZStack(alignment: .top) {
          LinearGradient(colors: [.indigo.opacity(0.7), .teal.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
          if style == .notch {
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
              .fill(.black).frame(width: 74, height: 15)
          } else {
            Capsule().fill(.black).frame(width: 70, height: 17).padding(.top, 6)
          }
        }
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        Text(style.title).font(.system(size: 12, weight: .semibold))
      }
      .padding(6)
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  @ViewBuilder private var hiddenApps: some View {
    LabeledContent {
      Button("Add App…", action: chooseApp)
    } label: {
      Text("Hide while these apps are in front")
      if settings.shellHiddenApps.isEmpty {
        Text("None. Add games or presentation apps to keep the island out of the way.")
      }
    }
    let apps = settings.shellHiddenApps
    if !apps.isEmpty {
        ForEach(apps, id: \.self) { bundleID in
          HStack(spacing: 8) {
            Image(nsImage: Self.icon(for: bundleID)).resizable().frame(width: 20, height: 20)
            Text(Self.name(for: bundleID))
            Spacer()
            Button { remove(bundleID) } label: { Image(systemName: "minus.circle.fill") }
              .buttonStyle(.plain).foregroundStyle(.secondary)
              .accessibilityLabel("Remove \(Self.name(for: bundleID))")
          }
        }
    }
  }

  private func points(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
    slider(title, value, range, step: 1) { $0 == 0 ? "Standard" : String(format: "%+.0f pt", $0) }
  }

  private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double,
                      label: @escaping (Double) -> String) -> some View {
    LabeledContent(LocalizedStringKey(title)) {
      HStack(spacing: 10) {
        Slider(value: value, in: range, step: step).frame(maxWidth: 260)
        Text(label(value.wrappedValue)).monospacedDigit()
          .foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
          .contentTransition(.numericText())
      }
    }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  // MARK: State

  private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
    Binding(
      get: { settings[keyPath: keyPath] },
      set: { value in
        settings[keyPath: keyPath] = value
        revision += 1
        if notifies { NotchShelfController.shared.settingsChanged() }
      })
  }

  private var sizesAreDefault: Bool {
    settings.shellIslandWidthOffset == 0 && settings.shellIslandHeightOffset == 0
      && settings.shellIslandVerticalOffset == 0 && settings.shellNotchWidthOffset == 0
      && settings.shellNotchHeightOffset == 0
  }

  private func resetSizes() {
    settings.shellIslandWidthOffset = 0
    settings.shellIslandHeightOffset = 0
    settings.shellIslandVerticalOffset = 0
    settings.shellNotchWidthOffset = 0
    settings.shellNotchHeightOffset = 0
    revision += 1
    if notifies { NotchShelfController.shared.settingsChanged() }
  }

  private func remove(_ bundleID: String) {
    settings.shellHiddenApps = settings.shellHiddenApps.filter { $0 != bundleID }
    revision += 1
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.prompt = "Hide in App"
    guard panel.runModal() == .OK else { return }
    var apps = settings.shellHiddenApps
    for url in panel.urls {
      guard let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) else { continue }
      apps.append(id)
    }
    settings.shellHiddenApps = apps
    revision += 1
  }

  private static func appURL(_ bundleID: String) -> URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
  }

  private static func icon(for bundleID: String) -> NSImage {
    appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
      ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
  }

  private static func name(for bundleID: String) -> String {
    appURL(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
      ?? bundleID
  }
}
