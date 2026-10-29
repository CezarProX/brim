// FeatureIconCatalog.swift
// Brim
//
// Which icon each feature wears. Real Apple icons wherever a feature maps to an Apple app or a
// System Settings pane; custom `AppleIconArt` (same grid and lighting) for everything else.
// Every real icon carries custom fallback art for Macs that lack it.

import SwiftUI

/// The custom art palette: Apple system hues, a lighter top over the system color below.
enum IconArt {
  private static let hex = AppleIconArt.hex

  static let clipboard = AppleIconArt("list.clipboard.fill", hex(0x7D7AFF), hex(0x5856D6), glyphScale: 1.12)
  static let lyrics = AppleIconArt("quote.bubble.fill", hex(0xFF6B8A), hex(0xFF2D55))
  static let highAlert = AppleIconArt("cup.and.saucer.fill", hex(0xFFB14A), hex(0xFF8A1F), glyphScale: 1.02)
  static let textCapture = AppleIconArt("text.viewfinder", hex(0x5FE3D6), hex(0x00B8B0))
  static let teleprompter = AppleIconArt("text.justify.left", hex(0xD98BFF), hex(0xAF52DE), glyphScale: 0.9)
  static let dropClip = AppleIconArt("text.cursor", hex(0x6EE7B7), hex(0x10B981), glyphScale: 0.95)
  static let emoji = AppleIconArt("face.smiling.inverse", hex(0xFFD43B), hex(0xFFA41B))
  static let cleaner = AppleIconArt("trash.fill", hex(0xFF7A70), hex(0xFF3B30), glyphScale: 0.92)
  static let removeBackground = AppleIconArt(
    "person.fill", hex(0x7AA7FF), hex(0x3D6DF2), glyphScale: 0.92, decoration: .checkerboard)
  static let agents = AppleIconArt("sparkles", hex(0xF2A47F), hex(0xD9643A), glyphScale: 1.12)
  static let obsidian = AppleIconArt("diamond.fill", hex(0xA98BFF), hex(0x7C4DFF), glyphScale: 0.9)
  static let island = AppleIconArt("capsule.fill", hex(0x8E8BFF), hex(0x5E5CE6), glyphScale: 0.72)
  static let upload = AppleIconArt("icloud.and.arrow.up.fill", hex(0x6CB8FF), hex(0x2F7CF6))
  static let transform = AppleIconArt("tray.and.arrow.down.fill", hex(0x5AB0FF), hex(0x1A73E8))
  static let droplets = AppleIconArt("drop.fill", hex(0x6BD6FF), hex(0x0AA2E0), glyphScale: 0.95)
  static let connections = AppleIconArt("link", hex(0x6EDB8A), hex(0x2FB457), glyphScale: 0.92)
  static let about = AppleIconArt("info", hex(0xB4B4BA), hex(0x7C7C82), glyphScale: 0.85)
  static let menuBar = AppleIconArt("menubar.rectangle", hex(0x9C9CA3), hex(0x636368))
  static let actionRing = AppleIconArt("circle.circle.fill", hex(0xFF9F6B), hex(0xFF6A3D))
  static let mcp = AppleIconArt("point.3.connected.trianglepath.dotted", hex(0x8E8BFF), hex(0x5E5CE6))
  static let capture = AppleIconArt("camera.viewfinder", hex(0x6CB8FF), hex(0x2F7CF6))

  // Fallbacks for real icons, in case a Mac lacks the system app or pane.
  static let music = AppleIconArt("music.note", hex(0xFF5E7A), hex(0xFA243C))
  static let clock = AppleIconArt("clock.fill", hex(0x5A5A5F), hex(0x2C2C2E))
  static let screenshot = AppleIconArt("camera.viewfinder", hex(0x8E8E93), hex(0x48484A))
  static let timer = AppleIconArt("timer", hex(0xFFB340), hex(0xFF9500))
  static let notes = AppleIconArt("note.text", hex(0xFFDA4D), hex(0xF5B800))
  static let stats = AppleIconArt("waveform.path.ecg", hex(0x5BE37A), hex(0x26A645))
  static let calendar = AppleIconArt("calendar", hex(0xFF6B61), hex(0xFF3B30))
  static let battery = AppleIconArt("battery.100percent", hex(0x6EE07F), hex(0x30C24C))
  static let weather = AppleIconArt("cloud.sun.fill", hex(0x6CB8FF), hex(0x2F7CF6))
  static let recording = AppleIconArt("record.circle.fill", hex(0xFF6B61), hex(0xFF3B30))
  static let sound = AppleIconArt("speaker.wave.2.fill", hex(0xFF6B8A), hex(0xFF375F))
  static let airplay = AppleIconArt("airplayaudio", hex(0x5AB0FF), hex(0x0A84FF))
  static let terminal = AppleIconArt("terminal.fill", hex(0x5A5A5F), hex(0x2C2C2E))
  static let developer = AppleIconArt("hammer.fill", hex(0x8E8E93), hex(0x48484A))
  static let launcher = AppleIconArt("square.grid.3x3.fill", hex(0x8E8BFF), hex(0x5E5CE6))
  static let camera = AppleIconArt("camera.fill", hex(0x8E8E93), hex(0x48484A))
  static let voiceMemo = AppleIconArt("waveform", hex(0xFF6B61), hex(0xFF3B30))
  static let microphone = AppleIconArt("mic.fill", hex(0x8E8E93), hex(0x48484A))
  static let airdrop = AppleIconArt("dot.radiowaves.left.and.right", hex(0x5AB0FF), hex(0x0A84FF))
  static let frontApp = AppleIconArt("macwindow", hex(0x8E8E93), hex(0x48484A))
  static let gear = AppleIconArt("gearshape.fill", hex(0x9C9CA3), hex(0x636368))
  static let keyboard = AppleIconArt("keyboard.fill", hex(0x9C9CA3), hex(0x636368))
  static let folder = AppleIconArt("folder.fill", hex(0x6CB8FF), hex(0x2F7CF6))
  static let appearance = AppleIconArt("circle.lefthalf.filled", hex(0x5A5A5F), hex(0x2C2C2E))
  static let liveActivities = AppleIconArt("bolt.fill", hex(0x6CB8FF), hex(0x2F7CF6))
  static let display = AppleIconArt("sun.max.fill", hex(0x6CB8FF), hex(0x2F7CF6))
  static let widgets = AppleIconArt("square.grid.2x2.fill", hex(0x8E8BFF), hex(0x5E5CE6))
  static let notifications = AppleIconArt("bell.badge.fill", hex(0xFF6B61), hex(0xFF3B30))
  static let lock = AppleIconArt("lock.fill", hex(0x5A5A5F), hex(0x2C2C2E))
  static let reminders = AppleIconArt("checklist", hex(0x6CB8FF), hex(0x2F7CF6))
}

extension HomeWidget {
  var icon: FeatureIcon {
    switch self {
    case .media: .real(.systemApp("Music"), fallback: IconArt.music)
    case .clock: .real(.systemApp("Clock"), fallback: IconArt.clock)
    case .captures: .real(.utility("Screenshot"), fallback: IconArt.screenshot)
    case .timer: .real(.settings("timer"), fallback: IconArt.timer)
    case .notes: .real(.systemApp("Notes"), fallback: IconArt.notes)
    case .stats: .real(.utility("Activity Monitor"), fallback: IconArt.stats)
    case .agenda: .real(.systemApp("Calendar"), fallback: IconArt.calendar)
    case .batteries: .real(.settings("battery"), fallback: IconArt.battery)
    case .awake: .custom(IconArt.highAlert)
    case .weather: .real(.systemApp("Weather"), fallback: IconArt.weather)
    case .lyrics: .custom(IconArt.lyrics)
    }
  }
}

extension IslandWidgetTile {
  var icon: FeatureIcon {
    switch self {
    case .recording: .real(.settings("screen-recording"), fallback: IconArt.recording)
    case .weather: .real(.systemApp("Weather"), fallback: IconArt.weather)
    case .nowPlaying: .real(.systemApp("Music"), fallback: IconArt.music)
    case .clipboard: .custom(IconArt.clipboard)
    case .calendar: .real(.systemApp("Calendar"), fallback: IconArt.calendar)
    case .timer: .real(.settings("timer"), fallback: IconArt.timer)
    case .notes: .real(.systemApp("Notes"), fallback: IconArt.notes)
    case .obsidian: .real(.bundleID("md.obsidian"), fallback: IconArt.obsidian)
    case .stats: .real(.utility("Activity Monitor"), fallback: IconArt.stats)
    case .textCapture: .custom(IconArt.textCapture)
    case .audioControl: .real(.settings("sound"), fallback: IconArt.sound)
    case .airPlayRooms: .real(.settings("airplay-audio"), fallback: IconArt.airplay)
    case .termiNotch: .real(.utility("Terminal"), fallback: IconArt.terminal)
    case .teleprompter: .custom(IconArt.teleprompter)
    case .dropClip: .custom(IconArt.dropClip)
    case .emojiPicker: .custom(IconArt.emoji)
    // Xcode's own icon is unreliable across betas; the Developer Tools pane icon always draws.
    case .xcodeBuilds: .real(.settings("developer-tools"), fallback: IconArt.developer)
    case .launcher: .real(.systemApp("Apps"), fallback: IconArt.launcher)
    case .cleaner: .custom(IconArt.cleaner)
    case .menuBarManager: .real(.settings("control-center"), fallback: IconArt.menuBar)
    case .removeBackground: .custom(IconArt.removeBackground)
    case .agents: .custom(IconArt.agents)
    case .keepAwake: .custom(IconArt.highAlert)
    case .camera: .real(.settings("camera"), fallback: IconArt.camera)
    case .voiceMemo: .real(.systemApp("VoiceMemos"), fallback: IconArt.voiceMemo)
    case .dictation: .real(.settings("microphone"), fallback: IconArt.microphone)
    case .devices: .real(.settings("battery"), fallback: IconArt.battery)
    case .share: .real(.settings("airdrop"), fallback: IconArt.airdrop)
    case .frontApp: .real(.systemApp("Mission Control"), fallback: IconArt.frontApp)
    case .screenshot: .real(.utility("Screenshot"), fallback: IconArt.screenshot)
    }
  }
}

extension SettingsPane {
  var icon: FeatureIcon {
    switch self {
    case .general: .real(.settings("gear"), fallback: IconArt.gear)
    case .capture: .real(.utility("Screenshot"), fallback: IconArt.capture)
    case .shortcut: .real(.settings("keyboard"), fallback: IconArt.keyboard)
    case .island: .custom(IconArt.island)
    case .widgets: .real(.settings("home-screen"), fallback: IconArt.widgets)
    case .media: .real(.systemApp("Music"), fallback: IconArt.music)
    case .hud: .real(.settings("live-activities"), fallback: IconArt.liveActivities)
    case .notifications: .real(.settings("notifications"), fallback: IconArt.notifications)
    case .lockScreen:
      .real(.app("/System/Library/ExtensionKit/Extensions/LockScreen.appex"), fallback: IconArt.lock)
    case .clipboard: .custom(IconArt.clipboard)
    case .about: .custom(IconArt.about)
    }
  }
}

/// A Home widget's icon (real Apple icon or matching custom art) with a visible tile `size` wide.
/// Used by the Home edit dock.
struct HomeWidgetIcon: View {
  let widget: HomeWidget
  var size: CGFloat = 36

  var body: some View {
    FeatureIconView(widget.icon, size: size)
  }
}
