// ShellExtrasSettingsSection.swift
// Brim
//
// Island options: what a notch click does, the navigation capsule and its pinned favorites,
// hold-to-reveal, open size, per-display visibility and the black menu-bar band.

import AppKit
import SwiftUI

struct ShellExtrasSettingsSection: View {
  @State private var revision = 0
  private let settings: AppSettings
  private let notifies: Bool
  private let part: SettingsPart?

  init(settings: AppSettings = .shared, notifies: Bool = true, part: SettingsPart? = nil) {
    self.settings = settings
    self.notifies = notifies
    self.part = part
  }

  var body: some View {
    let _ = revision
    Group {
      if part != .advanced { sizeSection }
      if part != .basic {
        clickSection
        navigationSection
        displaysSection
      }
    }
  }

  private var clickSection: some View {
    SettingsSection(
      "Click and reveal",
      footer: "Hold the key near the top of the display to open the island even when hover-open is off. A click on the closed notch uses the action above; with hover-open on the island is usually open before you click."
    ) {
      row("On notch click") {
        Picker("", selection: binding(\.shellClickAction)) {
          ForEach(ShellClickAction.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden().frame(width: 200)
      }
      if settings.shellClickAction == .openPage {
        row("Page") {
          Picker("", selection: binding(\.shellClickPage)) {
            ForEach(IslandPage.allCases, id: \.self) { Text($0.title).tag($0.storedName) }
          }
          .pickerStyle(.segmented).labelsHidden().frame(width: 410)
        }
      }
      row("Hold to reveal") {
        Picker("", selection: binding(\.shellRevealModifier)) {
          ForEach(ShellRevealModifier.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden().frame(width: 200)
      }
    }
  }

  private var navigationSection: some View {
    section("Navigation and favorites") {
      Toggle(isOn: binding(\.shellShowNavigation)) {
        Text("Show navigation")
        Text(settings.shellShowNavigation
          ? "The Home, Tray and Widgets buttons under the open island."
          : "Navigation is hidden: switch pages with a two-finger swipe, and keep the swipe setting on.")
      }
      if settings.shellShowNavigation {
        VStack(alignment: .leading, spacing: 8) {
          Text("Pinned beside navigation (up to \(AppSettings.shellMaxFavorites))")
          favoritesGrid
        }
      }
    }
  }

  private var favoritesGrid: some View {
    let pinned = IslandFavorites.tiles(from: settings.shellPinnedFavorites)
    let full = pinned.count >= AppSettings.shellMaxFavorites
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 2) {
      ForEach(IslandWidgetTile.allCases.filter(\.opensInIsland)) { tile in
        let isPinned = pinned.contains(tile)
        Button { toggleFavorite(tile) } label: {
          HStack(spacing: 6) {
            IslandWidgetIcon(tile: tile, size: 16)
            Text(tile.title).font(.callout).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(isPinned ? Color.accentColor : Color.secondary.opacity(0.5))
          }
          .padding(.horizontal, 8).padding(.vertical, 5)
          .background(isPinned ? Color.accentColor.opacity(0.12) : .clear,
                      in: RoundedRectangle(cornerRadius: 7, style: .continuous))
          .contentShape(Rectangle())
          .opacity(!isPinned && full ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isPinned && full)
        .accessibilityAddTraits(isPinned ? .isSelected : [])
      }
    }
  }

  private var sizeSection: some View {
    SettingsSection(
      "Open size and notch",
      footer: "Paints the menu bar black on notched Macs so the camera housing blends in. Fullscreen apps are unaffected."
    ) {
      row("Open size") {
        Picker("", selection: binding(\.shellOpenSize)) {
          ForEach(ShellOpenSize.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 200)
      }
      Toggle("Hide the physical notch", isOn: binding(\.shellHidePhysicalNotch))
    }
  }

  @ViewBuilder
  private var displaysSection: some View {
    let screens = NSScreen.screens
    if screens.count > 1 {
      section("Show on these displays") {
        ForEach(Array(screens.enumerated()), id: \.offset) { _, screen in
          if let uuid = ShellEnvironment.displayID(of: screen).flatMap(ShellEnvironment.displayUUID) {
            Toggle(screen.localizedName, isOn: Binding(
              get: { !settings.shellDisabledDisplays.contains(uuid) },
              set: { setDisplay(uuid, visible: $0) }))
          }
        }
        note("Turn a display off to keep the island away from it.")
      }
    }
  }

  private func toggleFavorite(_ tile: IslandWidgetTile) {
    settings.shellPinnedFavorites = IslandFavorites.toggled(tile, in: settings.shellPinnedFavorites)
    revision += 1
    if notifies { NotchShelfController.shared.settingsChanged() }
  }

  private func setDisplay(_ uuid: String, visible: Bool) {
    var disabled = settings.shellDisabledDisplays.filter { $0 != uuid }
    if !visible { disabled.append(uuid) }
    settings.shellDisabledDisplays = disabled
    revision += 1
    if notifies { NotchShelfController.shared.settingsChanged() }
  }

  private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
    Binding(
      get: { settings[keyPath: keyPath] },
      set: { value in
        settings[keyPath: keyPath] = value
        revision += 1
        if notifies { NotchShelfController.shared.settingsChanged() }
      })
  }

  private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    LabeledContent(LocalizedStringKey(title)) { content() }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}
