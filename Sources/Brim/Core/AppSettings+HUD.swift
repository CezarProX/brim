import AppKit
import SwiftUI

/// Where a level HUD sits relative to the closed notch.
enum HUDPlacement: String, CaseIterable, Identifiable {
  case besideNotch, belowNotch
  var id: String { rawValue }
  var title: String { self == .besideNotch ? "Beside the notch" : "Below the notch" }
}

/// Slider colors are stored as `#RRGGBB` so they survive export and stay human-readable.
enum HUDTint {
  static let volumeDefault = "#34C759"
  static let brightnessDefault = "#FFD60A"
  static let presets = ["#34C759", "#FFD60A", "#FFFFFF", "#0A84FF", "#FF9F0A", "#FF375F", "#64D2FF", "#BF5AF2"]

  static func color(hex: String) -> Color {
    guard let rgb = components(hex: hex) else { return .white }
    return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: 1)
  }

  static func components(hex: String) -> (Double, Double, Double)? {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
  }

  static func hex(from color: Color) -> String {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
    func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent))
  }
}

/// System HUDs and Live Activities settings (the "Live Activities" page).
extension AppSettings {
  private func flag(_ key: String, default value: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? value
  }

  /// Replacing a macOS pop-up needs an event tap, which needs Accessibility; off until chosen.
  var hudReplaceVolume: Bool {
    get { flag("hudReplaceVolume", default: true) }
    set { defaults.set(newValue, forKey: "hudReplaceVolume") }
  }
  var hudReplaceBrightness: Bool {
    get { flag("hudReplaceBrightness", default: true) }
    set { defaults.set(newValue, forKey: "hudReplaceBrightness") }
  }
  var hudReplaceKeyboardBacklight: Bool {
    get { flag("hudReplaceKeyboardBacklight", default: true) }
    set { defaults.set(newValue, forKey: "hudReplaceKeyboardBacklight") }
  }
  /// Also show the volume HUD when the volume changes from the menu bar or another app.
  var hudObserveVolume: Bool {
    get { flag("hudObserveVolume", default: true) }
    set { defaults.set(newValue, forKey: "hudObserveVolume") }
  }
  var hudQuitGuard: Bool {
    get { flag("hudQuitGuard", default: false) }
    set { defaults.set(newValue, forKey: "hudQuitGuard") }
  }

  var hudWiFi: Bool {
    get { flag("hudWiFi", default: true) }
    set { defaults.set(newValue, forKey: "hudWiFi") }
  }
  var hudOffline: Bool {
    get { flag("hudOffline", default: true) }
    set { defaults.set(newValue, forKey: "hudOffline") }
  }
  var hudVPN: Bool {
    get { flag("hudVPN", default: true) }
    set { defaults.set(newValue, forKey: "hudVPN") }
  }
  var hudDrives: Bool {
    get { flag("hudDrives", default: true) }
    set { defaults.set(newValue, forKey: "hudDrives") }
  }
  var hudBluetooth: Bool {
    get { flag("hudBluetooth", default: true) }
    set { defaults.set(newValue, forKey: "hudBluetooth") }
  }
  var hudFocus: Bool {
    get { flag("hudFocus", default: true) }
    set { defaults.set(newValue, forKey: "hudFocus") }
  }

  /// The Mac is online through a phone's Personal Hotspot: a notice, then a quiet "Active" activity.
  var hudHotspot: Bool {
    get { flag("hudHotspot", default: true) }
    set { defaults.set(newValue, forKey: "hudHotspot") }
  }
  /// "Full Battery" card when a charging Mac reaches 100%.
  var hudFullBattery: Bool {
    get { flag("hudFullBattery", default: true) }
    set { defaults.set(newValue, forKey: "hudFullBattery") }
  }
  /// A quiet green or orange activity for as long as the camera or microphone is in use.
  var hudPrivacyIndicator: Bool {
    get { flag("hudPrivacyIndicator", default: true) }
    set { defaults.set(newValue, forKey: "hudPrivacyIndicator") }
  }
  /// A notice when a newer version appears in the update feed.
  var hudUpdate: Bool {
    get { flag("hudUpdate", default: true) }
    set { defaults.set(newValue, forKey: "hudUpdate") }
  }

  var hudPlacement: HUDPlacement {
    get { HUDPlacement(rawValue: defaults.string(forKey: "hudPlacement") ?? "") ?? .besideNotch }
    set { defaults.set(newValue.rawValue, forKey: "hudPlacement") }
  }
  var hudVolumeTintHex: String {
    get { defaults.string(forKey: "hudVolumeTint") ?? HUDTint.volumeDefault }
    set { defaults.set(newValue, forKey: "hudVolumeTint") }
  }
  var hudBrightnessTintHex: String {
    get { defaults.string(forKey: "hudBrightnessTint") ?? HUDTint.brightnessDefault }
    set { defaults.set(newValue, forKey: "hudBrightnessTint") }
  }
}
