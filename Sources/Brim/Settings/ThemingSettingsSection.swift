// ThemingSettingsSection.swift
// Brim
//
// Settings > Theming: how the open island is painted (Black, Dynamic Glass, Liquid Glass),
// where the black melts into glass, and tinted or clear glass. Changes show on the island at once.

import SwiftUI

struct ThemingSettingsSection: View {
  @ObservedObject var theme: IslandTheme = .shared

  /// nil shows everything; the Island page shows the surface and glass, the rest under Advanced.
  var part: SettingsPart?

  var body: some View {
    Group {
      if part != .advanced { surfaceSections }
      if part != .basic { advancedSections }
    }
    .animation(.easeInOut(duration: 0.2), value: theme.surface)
  }

  @ViewBuilder private var surfaceSections: some View {
      section("Island surface") {
        Picker("Surface", selection: Binding(get: { theme.surface }, set: theme.setSurface)) {
          ForEach(IslandSurfaceStyle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        ThemingPreview(theme: theme)
          .frame(height: 120)
        note(surfaceNote)
      }
      if theme.surface == .dynamicGlass {
        section("Glass level") {
          Slider(value: Binding(get: { theme.glassLevel }, set: theme.setGlassLevel), in: 0...1) {
            Text("Glass level")
          } minimumValueLabel: {
            Text("More black").font(.footnote).foregroundStyle(.secondary)
          } maximumValueLabel: {
            Text("More glass").font(.footnote).foregroundStyle(.secondary)
          }
          note("Where the black at the top melts into glass. Open the island to see it change live.")
        }
      }
      if theme.surface.usesGlass {
        section("Glass") {
          Toggle("Tinted glass", isOn: Binding(get: { theme.tinted }, set: theme.setTinted))
          note("Tinted glass keeps text readable on any wallpaper, on the island, its panels and in Settings. Turn it off for clear glass.")
          Slider(value: Binding(get: { theme.clarity }, set: theme.setClarity), in: 0...1) {
            Text("Clarity")
          } minimumValueLabel: {
            Text("Frosted").font(.footnote).foregroundStyle(.secondary)
          } maximumValueLabel: {
            Text("Clear").font(.footnote).foregroundStyle(.secondary)
          }
          Toggle("Light glass in Light mode", isOn: Binding(get: { theme.lightGlassInLightMode }, set: theme.setLightGlass))
          note("With macOS in Light appearance the glass turns pale and frosted. Text stays white, so the veil is kept dark enough to read.")
        }
      }
  }

  @ViewBuilder private var advancedSections: some View {
      section("Colors") {
        colorRow("Highlight", "Selection, sliders and toggles in the island.", hex: theme.highlightHex, set: theme.setHighlight)
        if theme.surface.usesGlass {
          colorRow("Window tint", "A wash of color over the glass.", hex: theme.windowTintHex, set: theme.setWindowTint)
        }
      }
      section("Effects") {
        Toggle("Progressive blur around the island", isOn: Binding(get: { theme.progressiveBlur }, set: theme.setProgressiveBlur))
        Toggle("Lighter visuals on low battery", isOn: Binding(get: { theme.lowBatteryEnabled }, set: theme.setLowBattery))
        note(theme.lowBatteryActive
          ? "Active now: the island is solid black with no blur until the battery is charged or Low Power Mode is off."
          : "Switches to solid black with no blur when the battery drops under 20% or Low Power Mode is on.")
      }
      AppIconSettingsSection()
  }

  private func colorRow(_ title: String, _ detail: String, hex: String, set: @escaping (String) -> Void) -> some View {
    LabeledContent {
      HStack(spacing: 8) {
        if !hex.isEmpty { Button("Reset") { set("") } }
        ColorPicker(title, selection: Binding(
          get: { IslandHex.color(hex) ?? .white }, set: { set(IslandHex.string(from: $0)) }), supportsOpacity: false)
          .labelsHidden()
      }
    } label: {
      Text(LocalizedStringKey(title))
      Text(LocalizedStringKey(detail))
    }
  }

  private var surfaceNote: String {
    switch theme.surface {
    case .black: "Solid black, like the hardware notch."
    case .dynamicGlass: "Black at the top blends with the notch and melts into blurred glass toward the bottom."
    case .liquidGlass: "Glass from edge to edge; only the band behind the camera stays black."
    }
  }
}

/// A small live sample of the chosen surface over a colourful backdrop.
private struct ThemingPreview: View {
  @ObservedObject var theme: IslandTheme

  var body: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [Color(red: 0.12, green: 0.14, blue: 0.85), Color(red: 0.55, green: 0.3, blue: 0.9)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(Color.pink.opacity(0.7)).frame(width: 90).blur(radius: 18).offset(x: -90, y: 50)
      Circle().fill(Color.cyan.opacity(0.7)).frame(width: 80).blur(radius: 16).offset(x: 110, y: 40)
      sample
    }
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityHidden(true)
  }

  private var sample: some View {
    let shape = UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
    return ZStack {
      if theme.surface.usesGlass {
        Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, theme.usesLightGlass ? .light : .dark)
        let veil = GlassClarity(theme.clarity).veilOpacity(tinted: theme.tinted)
        // The same readable tint the island paints with (`GlassStyle`).
        let darkVeil = GlassPreferences(tinted: theme.tinted, clarity: theme.clarity)
          .veil(for: .shell, materialGray: GlassMaterialGray.hudWindow)
        if theme.usesLightGlass { Color(white: 0.34).opacity(veil + 0.14) } else { Color.black.opacity(darkVeil) }
        if let tint = theme.windowTint { tint.opacity(0.28).blendMode(.plusLighter) }
      }
      GeometryReader { proxy in
        LinearGradient(
          gradient: DynamicGlassMelt(style: theme.surface, height: proxy.size.height, solidHeight: 22,
                                     level: theme.glassLevel, lightness: theme.usesLightGlass ? 1 : 0).gradient,
          startPoint: .top, endPoint: .bottom)
      }
      Text("Kill Bill · SZA").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
    }
    .frame(width: 260, height: 96)
    .clipShape(shape)
  }
}

private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
  SettingsSection(title) { content() }
}

private func note(_ text: String) -> some View {
  SettingsFootnote(text)
}
