import AppKit
import SwiftUI

/// The Audio Control droplet, shown inside the open island (about 560 x 200 pt of content).
struct AudioControlView: View {
  @ObservedObject var model: AudioControlModel = .shared
  @ObservedObject var microphones: MicrophoneMuteController = .shared
  /// Off inside the island's opened-widget frame, which already shows the title.
  var showsTitle = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let preferredSize = CGSize(width: 560, height: 200)
  private let rowHeight: CGFloat = 46

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(IslandFill.hairline).padding(.horizontal, IslandSpace.l)
      content
    }
    .frame(maxWidth: Self.preferredSize.width)
    .frame(height: Self.preferredSize.height, alignment: .top)
    .onAppear { model.setActive(true) }
    .onDisappear { model.setActive(false) }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack(spacing: IslandSpace.s) {
      if showsTitle {
        Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(IslandTint.audio)
        Text("Audio Control").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      }
      Spacer()
      Button { microphones.toggle() } label: {
        Label(microphones.isMuted ? "Mics muted" : "Mute mics", systemImage: microphones.isMuted ? "mic.slash.fill" : "mic.fill")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(IslandAppPillStyle(prominent: microphones.isMuted, tint: .red))
      .help("Mute every microphone")
    }
    .padding(.horizontal, IslandSpace.l).frame(height: 38)
  }

  static let note = Font.system(size: 12, weight: .medium)

  @ViewBuilder private var content: some View {
    if !model.isSupported {
      EmptyState(symbol: "exclamationmark.triangle", title: "Needs macOS 14.2 or newer",
                 detail: "Per-app volume uses Core Audio process taps, which older macOS versions do not have.")
    } else if model.rows.isEmpty {
      EmptyState(symbol: "speaker.zzz.fill", title: "Nothing is playing",
                 detail: "Play music or a video. The app shows up here with its own volume slider.")
    } else {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 2) {
          ForEach(model.rows) { row in
            AudioAppRowView(row: row, model: model).frame(height: rowHeight)
              .transition(.opacity.combined(with: .scale(scale: 0.97)))
          }
        }
        .padding(.horizontal, IslandSpace.s).padding(.vertical, IslandSpace.xs)
        .animation(reduceMotion ? nil : NotchMotion.layout(reduceMotion: false), value: model.rows.map(\.id))
      }
      footer
    }
  }

  /// One line of setup: the permission fix when macOS refused, otherwise what the first drag does.
  @ViewBuilder private var footer: some View {
    if model.needsPermission {
      HStack(spacing: IslandSpace.s) {
        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Color.orange)
        Text("Allow Brim under System Audio Recording").font(Self.note)
          .foregroundStyle(IslandInk.primary).lineLimit(1).minimumScaleFactor(0.85)
        Spacer(minLength: 0)
        Button("Open Settings") { Self.openAudioPrivacy() }
          .buttonStyle(IslandAppPillStyle(prominent: true, tint: .orange))
      }
      .padding(.horizontal, IslandSpace.l).frame(height: 34)
      .background(Color.orange.opacity(0.12))
    } else if model.isUntouched {
      Text("Drag a slider to change an app. macOS asks once to allow System Audio Recording.")
        .font(Self.note).foregroundStyle(IslandInk.tertiary).lineLimit(1).minimumScaleFactor(0.85)
        .padding(.horizontal, IslandSpace.l).frame(height: 28)
    }
  }

  static func openAudioPrivacy() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
      NSWorkspace.shared.open(url)
    }
  }
}

private struct EmptyState: View {
  let symbol: String
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(IslandInk.tertiary)
      Text(title).font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      Text(detail).font(AudioControlView.note).foregroundStyle(IslandInk.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct AudioAppRowView: View {
  let row: AudioAppRow
  @ObservedObject var model: AudioControlModel
  @State private var hovering = false

  private var sliderBinding: Binding<Double> {
    Binding(get: { row.muted ? 0 : row.slider }, set: { model.setSlider(row.id, $0) })
  }

  var body: some View {
    HStack(spacing: IslandSpace.m) {
      AppIcon(bundleID: row.id, isSystem: row.entry.isSystemSounds)
        .frame(width: 30, height: 30).opacity(row.entry.isPlaying ? 1 : 0.55)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.entry.name).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(row.error == nil ? IslandInk.secondary : Color.orange)
          .lineLimit(1)
      }
      .frame(width: 138, alignment: .leading)
      AudioSlider(value: sliderBinding, maximum: model.maxSlider, tint: row.muted ? IslandInk.tertiary : .white)
      Text(AudioGainMath.percentLabel(row.muted ? 0 : row.slider)).font(IslandFont.label.monospacedDigit())
        .foregroundStyle(IslandInk.secondary).contentTransition(.numericText())
        .frame(width: 40, alignment: .trailing)
      iconButton(row.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: row.muted,
                 help: row.muted ? "Unmute" : "Mute") { model.toggleMute(row.id) }
      outputMenu
    }
    .padding(.horizontal, IslandSpace.s)
    .background(RoundedRectangle(cornerRadius: IslandRadius.small).fill(hovering ? IslandFill.subtle : .clear))
    .onHover { hovering = $0 }
  }

  private var subtitle: String {
    if row.needsPermission { return "Needs permission" }
    if let error = row.error { return error }
    if row.muted { return "Muted" }
    if let uid = row.outputUID, let device = model.outputs.first(where: { $0.uid == uid }) { return "→ \(device.name)" }
    return row.entry.isPlaying ? "Playing" : "Paused"
  }

  private func iconButton(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        .foregroundStyle(active ? Color.red : IslandInk.secondary).frame(width: 28, height: 28)
        .background(Circle().fill(active ? Color.red.opacity(0.18) : IslandFill.subtle))
    }
    .buttonStyle(IslandPressStyle()).help(help).accessibilityLabel(help)
  }

  private var outputMenu: some View {
    Menu {
      Button { model.setOutput(row.id, uid: nil) } label: {
        Label("System default", systemImage: row.outputUID == nil ? "checkmark" : "speaker.wave.2")
      }
      Divider()
      ForEach(model.outputs) { device in
        Button { model.setOutput(row.id, uid: device.uid) } label: {
          Label(device.name, systemImage: row.outputUID == device.uid ? "checkmark" : (device.isBluetooth ? "headphones" : "hifispeaker"))
        }
      }
      if !row.isNeutral { Divider(); Button("Reset") { model.reset(row.id) } }
    } label: {
      Image(systemName: row.outputUID == nil ? "airplayaudio" : "airplayaudio.circle.fill")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(row.outputUID == nil ? IslandInk.secondary : IslandTint.audio)
        .frame(width: 28, height: 28).background(Circle().fill(IslandFill.subtle))
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Output for this app")
  }
}

struct AppIcon: View {
  let bundleID: String
  var isSystem = false

  var body: some View {
    if isSystem {
      Image(systemName: "bell.fill").font(.system(size: 14)).foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [.gray, .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom)))
    } else if let icon = Self.icon(for: bundleID) {
      Image(nsImage: icon).resizable().scaledToFit()
    } else {
      Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(IslandInk.tertiary)
    }
  }

  static func icon(for bundleID: String) -> NSImage? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
  }
}

extension IslandTint {
  /// Audio Control / output accent.
  static let audio = Color(red: 0.36, green: 0.78, blue: 1.0)
}
