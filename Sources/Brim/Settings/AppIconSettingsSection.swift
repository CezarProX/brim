// AppIconSettingsSection.swift
// Brim
//
// Settings > Theming > App icon: a row of previews; clicking one applies it to the running app at once
// and keeps it for the next launch.

import SwiftUI

struct AppIconSettingsSection: View {
  @State private var selected = AppSettings.shared.appIconVariant

  var body: some View {
    SettingsSection("App icon", footer: "Shown in the Dock and the app switcher. The change applies right away.") {
      HStack(spacing: 12) {
        ForEach(AppIconVariant.allCases) { variant in
          tile(variant)
        }
      }
    }
  }

  private func tile(_ variant: AppIconVariant) -> some View {
    let isSelected = selected == variant
    return Button {
      selected = variant
      AppIconController.select(variant)
    } label: {
      VStack(spacing: 6) {
        Image(nsImage: AppIconRenderer.image(for: variant, size: 128))
          .resizable().frame(width: 64, height: 64)
          .padding(4)
          .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5))
        Text(variant.title).font(.caption).foregroundStyle(isSelected ? .primary : .secondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(variant.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
