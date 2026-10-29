// SettingsHeroArt.swift
// Brim
//
// The picture at the top of each Settings page: a small desktop with the island showing what the
// page controls (the Home grid, a volume HUD, a song, a notification...), drawn from the same real
// icons the app uses, so the page says at a glance what it is about.

import SwiftUI

struct SettingsHeroArt: View {
  let pane: SettingsPane

  static let size = CGSize(width: 300, height: 128)

  var body: some View {
    ZStack(alignment: .top) {
      wallpaper
      scene
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    .accessibilityHidden(true)
  }

  /// A soft Tahoe-like wallpaper, tinted per page so pages feel distinct.
  private var wallpaper: some View {
    let (top, bottom) = pane.heroColors
    return ZStack {
      LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(.white.opacity(0.18)).frame(width: 220).blur(radius: 30).offset(x: -110, y: 60)
      Circle().fill(.white.opacity(0.12)).frame(width: 180).blur(radius: 26).offset(x: 130, y: -40)
    }
  }

  @ViewBuilder private var scene: some View {
    switch pane {
    case .general:
      island(width: 190, height: 58) {
        HStack(spacing: 10) {
          icon(IslandWidgetTile.screenshot.icon, 30)
          VStack(alignment: .leading, spacing: 4) {
            bar(70, 0.9)
            bar(46, 0.45)
          }
          Spacer(minLength: 0)
          icon(SettingsPane.general.icon, 22)
        }
      }
    case .capture:
      VStack(spacing: 0) {
        menuBar
        ZStack {
          RoundedRectangle(cornerRadius: 4).strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: 150, height: 66)
          icon(IslandWidgetTile.screenshot.icon, 34)
        }
        .padding(.top, 18)
      }
    case .shortcut:
      HStack(spacing: 8) {
        keycap("⇧"); keycap("⌘"); keycap("4")
      }
      .padding(.top, 40)
    case .island:
      island(width: 230, height: 76) {
        VStack(spacing: 10) {
          HStack(spacing: 14) {
            ForEach([IslandWidgetTile.nowPlaying, .calendar, .weather, .notes], id: \.self) { icon($0.icon, 26) }
          }
          HStack(spacing: 5) {
            Capsule().fill(.white.opacity(0.9)).frame(width: 16, height: 5)
            ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.35)).frame(width: 5, height: 5) }
          }
        }
      }
    case .widgets:
      island(width: 250, height: 84) {
        HStack(spacing: 8) {
          widgetCard(HomeWidget.clock.icon, lines: 2)
          widgetCard(HomeWidget.weather.icon, lines: 1)
          widgetCard(HomeWidget.agenda.icon, lines: 3)
        }
      }
    case .media:
      island(width: 230, height: 70) {
        HStack(spacing: 10) {
          icon(HomeWidget.media.icon, 40)
          VStack(alignment: .leading, spacing: 5) {
            bar(84, 0.9)
            bar(56, 0.45)
            Capsule().fill(.white.opacity(0.25)).frame(width: 110, height: 3)
              .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 46, height: 3) }
          }
          Spacer(minLength: 0)
          equalizer
        }
      }
    case .hud:
      island(width: 210, height: 40) {
        HStack(spacing: 10) {
          Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
          Capsule().fill(.white.opacity(0.22)).frame(height: 5)
            .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 96, height: 5) }
          Text("64").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
        }
      }
    case .notifications:
      island(width: 240, height: 62) {
        HStack(spacing: 10) {
          icon(.real(.systemApp("Messages"), fallback: IconArt.notifications), 34)
          VStack(alignment: .leading, spacing: 5) {
            bar(60, 0.95)
            bar(130, 0.5)
          }
          Spacer(minLength: 0)
        }
      }
    case .lockScreen:
      VStack(spacing: 2) {
        Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
        Text("9:41").font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.35))
          .frame(width: 170, height: 30)
          .overlay {
            HStack(spacing: 8) {
              icon(HomeWidget.media.icon, 18)
              bar(80, 0.8)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
          }
      }
      .padding(.top, 12)
    case .clipboard:
      island(width: 240, height: 74) {
        HStack(spacing: 8) {
          clip(color: .white, lines: 3)
          clip(color: Color(red: 1, green: 0.84, blue: 0.4), lines: 2)
          icon(.real(.app("/System/Library/CoreServices/Finder.app"), fallback: IconArt.folder), 34)
          clip(color: Color(red: 0.6, green: 0.8, blue: 1), lines: 2)
        }
      }
    case .about:
      VStack(spacing: 6) {
        Image(nsImage: AppIconRenderer.image(for: AppSettings.shared.appIconVariant, size: 128))
          .resizable().frame(width: 64, height: 64)
          .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
      }
      .padding(.top, 30)
    }
  }

  // MARK: Pieces

  /// The island hanging from the top edge: black, rounded below.
  private func island<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(.horizontal, 16)
      .frame(width: width, height: height)
      .background(
        UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous).fill(.black))
      .padding(.top, 0)
  }

  private var menuBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "apple.logo").font(.system(size: 9))
      bar(22, 0.8); bar(30, 0.6); bar(26, 0.6)
      Spacer()
      bar(34, 0.6)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .frame(height: 16)
    .background(.white.opacity(0.18))
  }

  private func icon(_ feature: FeatureIcon, _ size: CGFloat) -> some View {
    FeatureIconView(feature, size: size)
  }

  private func bar(_ width: CGFloat, _ opacity: Double) -> some View {
    Capsule().fill(.white.opacity(opacity)).frame(width: width, height: 5)
  }

  private func keycap(_ glyph: String) -> some View {
    Text(glyph)
      .font(.system(size: 22, weight: .medium, design: .rounded))
      .foregroundStyle(.black.opacity(0.75))
      .frame(width: 48, height: 44)
      .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
      .shadow(color: .black.opacity(0.25), radius: 0, y: 2)
  }

  private func widgetCard(_ feature: FeatureIcon, lines: Int) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      icon(feature, 22)
      ForEach(0..<lines, id: \.self) { index in bar(index == 0 ? 44 : 30, index == 0 ? 0.8 : 0.4) }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(width: 68, height: 64, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
  }

  private func clip(color: Color, lines: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(0..<lines, id: \.self) { index in
        Capsule().fill(Color.black.opacity(0.35)).frame(width: index == lines - 1 ? 18 : 28, height: 3)
      }
    }
    .padding(7)
    .frame(width: 42, height: 48, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
  }

  private var equalizer: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach([10.0, 18, 13, 20, 8], id: \.self) { height in
        Capsule().fill(Color(red: 1, green: 0.35, blue: 0.45)).frame(width: 3, height: height)
      }
    }
    .frame(height: 20, alignment: .bottom)
  }
}

private extension SettingsPane {
  /// Wallpaper colors for the page's picture.
  var heroColors: (Color, Color) {
    switch self {
    case .general, .about: (Color(red: 0.42, green: 0.55, blue: 0.95), Color(red: 0.62, green: 0.42, blue: 0.9))
    case .capture, .shortcut: (Color(red: 0.25, green: 0.62, blue: 0.98), Color(red: 0.36, green: 0.4, blue: 0.95))
    case .island, .widgets: (Color(red: 0.5, green: 0.42, blue: 0.98), Color(red: 0.3, green: 0.68, blue: 0.98))
    case .media: (Color(red: 0.98, green: 0.4, blue: 0.5), Color(red: 0.62, green: 0.36, blue: 0.95))
    case .hud: (Color(red: 0.2, green: 0.7, blue: 0.85), Color(red: 0.3, green: 0.45, blue: 0.95))
    case .notifications: (Color(red: 0.98, green: 0.5, blue: 0.4), Color(red: 0.95, green: 0.35, blue: 0.55))
    case .lockScreen: (Color(red: 0.18, green: 0.22, blue: 0.45), Color(red: 0.42, green: 0.3, blue: 0.7))
    case .clipboard: (Color(red: 0.98, green: 0.7, blue: 0.3), Color(red: 0.95, green: 0.45, blue: 0.35))
    }
  }
}
