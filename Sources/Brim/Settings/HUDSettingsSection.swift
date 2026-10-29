import SwiftUI

/// "Live Activities" list for system HUDs: what to replace, how it looks, and
/// which events get a HUD. Self-contained; the host places it in a settings page.
struct HUDSettingsSection: View {
  @ObservedObject private var controller = SystemHUDController.shared
  @State private var replaceVolume = AppSettings.shared.hudReplaceVolume
  @State private var replaceBrightness = AppSettings.shared.hudReplaceBrightness
  @State private var replaceKeyboard = AppSettings.shared.hudReplaceKeyboardBacklight
  @State private var observeVolume = AppSettings.shared.hudObserveVolume
  @State private var quitGuard = AppSettings.shared.hudQuitGuard
  @State private var wifi = AppSettings.shared.hudWiFi
  @State private var offline = AppSettings.shared.hudOffline
  @State private var vpn = AppSettings.shared.hudVPN
  @State private var drives = AppSettings.shared.hudDrives
  @State private var bluetooth = AppSettings.shared.hudBluetooth
  @State private var focus = AppSettings.shared.hudFocus
  @State private var fullBattery = AppSettings.shared.hudFullBattery
  @State private var hotspot = AppSettings.shared.hudHotspot
  @State private var privacyIndicator = AppSettings.shared.hudPrivacyIndicator
  @State private var updateNotice = AppSettings.shared.hudUpdate
  @State private var placement = AppSettings.shared.hudPlacement
  @State private var volumeTint = AppSettings.shared.hudVolumeTintHex
  @State private var brightnessTint = AppSettings.shared.hudBrightnessTintHex

  var body: some View {
    Group {
      group("Replace macOS pop-ups") {
        toggleRow("Replace the macOS volume pop-up", "Volume keys show the notch HUD instead. ⇧⌥ for fine steps.",
          symbol: "speaker.wave.2.fill", tint: .green, isOn: $replaceVolume) { AppSettings.shared.hudReplaceVolume = $0 }
        toggleRow("Show volume changes from elsewhere", "Menu bar slider, other apps and output switches.",
          symbol: "slider.horizontal.3", tint: .green, isOn: $observeVolume) { AppSettings.shared.hudObserveVolume = $0 }
          .disabled(!replaceVolume)
        toggleRow("Replace the macOS brightness pop-up", "Built-in display. External monitors keep the system pop-up.",
          symbol: "sun.max.fill", tint: .yellow, isOn: $replaceBrightness) { AppSettings.shared.hudReplaceBrightness = $0 }
        toggleRow("Replace the keyboard backlight pop-up", "Only on Macs with a backlight key; otherwise macOS handles it.",
          symbol: "light.max", tint: .orange, isOn: $replaceKeyboard) {
            AppSettings.shared.hudReplaceKeyboardBacklight = $0
          }
        toggleRow("Hold or press ⌘Q twice to quit", "The first ⌘Q shows a HUD; press again within 1.5 s, or hold.",
          symbol: "command", tint: .red, isOn: $quitGuard) { AppSettings.shared.hudQuitGuard = $0 }
        accessibilityRow
      }
      group("Appearance") {
        Picker(selection: $placement) {
          ForEach(HUDPlacement.allCases) { Text($0.title).tag($0) }
        } label: {
          Text("HUD placement")
          Text("Beside the notch keeps its height; Below drops under it.")
        }
        .onChange(of: placement) { _, value in AppSettings.shared.hudPlacement = value }
        tintRow("Volume slider color", hex: $volumeTint) { AppSettings.shared.hudVolumeTintHex = $0 }
        tintRow("Brightness slider color", hex: $brightnessTint) { AppSettings.shared.hudBrightnessTintHex = $0 }
      }
      SettingsSection(
        "Show a HUD when",
        footer: "Caps Lock, charging and camera or microphone flashes are in the Live Activities pane."
      ) {
        toggleRow("Wi-Fi network joined", "Shows the network name when macOS allows reading it. A phone hotspot's battery level isn't shown: macOS has no public API for it.",
          symbol: "wifi", tint: .blue, isOn: $wifi) { AppSettings.shared.hudWiFi = $0 }
        toggleRow("You go offline", "A “No Internet” notice after a short grace period.",
          symbol: "wifi.slash", tint: .orange, isOn: $offline) { AppSettings.shared.hudOffline = $0 }
        toggleRow("A VPN connects or disconnects", "Tunnel name, with how long it was up.",
          symbol: "lock.shield.fill", tint: .green, isOn: $vpn) { AppSettings.shared.hudVPN = $0 }
        toggleRow("A drive is connected", "Name and size, with an Eject button on the card.",
          symbol: "externaldrive.fill", tint: .gray, isOn: $drives) { AppSettings.shared.hudDrives = $0 }
        toggleRow("Bluetooth devices connect or run low", "Devices that report a battery level, checked every 20 s.",
          symbol: "headphones", tint: .blue, isOn: $bluetooth) { AppSettings.shared.hudBluetooth = $0 }
        toggleRow("Focus turns on or off", "Also shows a small Focus indicator while it is on. macOS has no Focus API: Brim asks permission to read it, or reads the Focus store with Full Disk Access.",
          symbol: "moon.fill", tint: .indigo, isOn: $focus) { AppSettings.shared.hudFocus = $0 }
        toggleRow("Your Mac is fully charged", "A Full Battery card when a charging Mac reaches 100%.",
          symbol: "battery.100percent.bolt", tint: .green, isOn: $fullBattery) { AppSettings.shared.hudFullBattery = $0 }
        toggleRow("You join a Personal Hotspot", "A notice, then an Active indicator while your Mac is online through a phone.",
          symbol: "personalhotspot", tint: .green, isOn: $hotspot) { AppSettings.shared.hudHotspot = $0 }
        toggleRow("The camera or microphone is in use", "A small indicator for as long as an app is using either.",
          symbol: "video.fill", tint: .green, isOn: $privacyIndicator) { AppSettings.shared.hudPrivacyIndicator = $0 }
        toggleRow("A new version is available", "From the update feed in Settings > About.",
          symbol: "arrow.down.circle.fill", tint: .blue, isOn: $updateNotice) { AppSettings.shared.hudUpdate = $0 }
      }
    }
  }

  // MARK: Rows

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  private func rowText(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(LocalizedStringKey(title))
      Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func toggleRow(
    _ title: String, _ detail: String, symbol: String, tint: Color, isOn: Binding<Bool>,
    apply: @escaping (Bool) -> Void
  ) -> some View {
    Toggle(isOn: isOn) {
      Label {
        Text(LocalizedStringKey(title))
        Text(LocalizedStringKey(detail))
      } icon: {
        FeatureIconView(.custom(AppleIconArt(symbol, tint.opacity(0.8), tint, glyphScale: 0.95)), size: 22)
      }
    }
    .onChange(of: isOn.wrappedValue) { _, value in
      apply(value)
      HUDCoordinator.refresh()
    }
  }

  @ViewBuilder
  private var accessibilityRow: some View {
    if (replaceVolume || replaceBrightness || replaceKeyboard || quitGuard) && !controller.tapRunning {
      HStack(spacing: 10) {
        Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
        rowText("Accessibility access needed", "macOS only lets apps intercept media keys and ⌘Q with it.")
        Spacer(minLength: 12)
        Button("Grant Accessibility") { controller.requestAccessibility() }
      }
    }
  }

  private func tintRow(_ title: String, hex: Binding<String>, apply: @escaping (String) -> Void) -> some View {
    LabeledContent(LocalizedStringKey(title)) {
      HStack(spacing: 6) {
      ForEach(HUDTint.presets, id: \.self) { preset in
        Button {
          hex.wrappedValue = preset
          apply(preset)
        } label: {
          Circle().fill(HUDTint.color(hex: preset)).frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.primary.opacity(preset == hex.wrappedValue ? 0.9 : 0.15), lineWidth: preset == hex.wrappedValue ? 2 : 1))
        }
        .buttonStyle(.plain).accessibilityLabel(preset)
      }
      ColorPicker("", selection: Binding(
        get: { HUDTint.color(hex: hex.wrappedValue) },
        set: { color in
          let value = HUDTint.hex(from: color)
          hex.wrappedValue = value
          apply(value)
        }), supportsOpacity: false)
        .labelsHidden()
      }
    }
  }
}
