import SwiftUI

/// One tile on the Widgets page. Tapping it opens that widget inside the island (back chevron
/// returns to the grid); Screenshot and Emoji Picker are actions and run instead.
enum IslandWidgetTile: String, CaseIterable, Identifiable, Hashable {
  case recording
  case weather, nowPlaying, clipboard, calendar, timer, notes, obsidian, stats
  case textCapture, audioControl, airPlayRooms, termiNotch, teleprompter, dropClip, emojiPicker, xcodeBuilds
  case launcher, cleaner, menuBarManager
  case removeBackground, agents, keepAwake, camera, voiceMemo, dictation, devices, share, frontApp, screenshot

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recording: "Recording"
    case .weather: "Weather"
    case .nowPlaying: "Now Playing"
    case .clipboard: "Clipboard"
    case .calendar: "Calendar"
    case .timer: "Pomodoro"
    case .notes: "Notes"
    case .obsidian: "Obsidian"
    case .stats: "System Stats"
    case .textCapture: "Text Capture"
    case .audioControl: "Audio Control"
    case .airPlayRooms: "AirPlay Rooms"
    case .termiNotch: "Termi-Notch"
    case .teleprompter: "Teleprompter"
    case .dropClip: "DropClip"
    case .emojiPicker: "Emoji Picker"
    case .xcodeBuilds: "Xcode Builds"
    case .launcher: "Launcher"
    case .cleaner: "Cleaner"
    case .menuBarManager: "Menu Bar"
    case .removeBackground: "Remove Background"
    case .agents: "Agents"
    case .keepAwake: "Stay Awake"
    case .camera: "Camera"
    case .voiceMemo: "Voice Memo"
    case .dictation: "Dictation"
    case .devices: "Batteries"
    case .share: "AirDrop"
    case .frontApp: "Front App"
    case .screenshot: "Screenshot"
    }
  }

  /// The live activity whose view this widget opens, where there is one.
  var activity: IslandActivity? {
    switch self {
    case .stats: .stats
    case .calendar: .calendar
    case .timer: .focus
    case .notes: .notes
    case .agents: .agent
    case .keepAwake: .keepAwake
    case .camera: .camera
    case .voiceMemo: .recorder
    case .dictation: .dictation
    case .devices: .devices
    case .share: .transfer
    case .frontApp: .workspace
    case .xcodeBuilds: .build
    case .recording, .weather, .nowPlaying, .clipboard, .obsidian, .textCapture, .audioControl, .airPlayRooms,
      .termiNotch, .teleprompter, .dropClip, .emojiPicker, .removeBackground, .screenshot, .launcher, .cleaner, .menuBarManager: nil
    }
  }

  /// The widget that shows a given activity (Home widgets and live activities open these).
  init?(activity: IslandActivity) {
    guard let tile = Self.allCases.first(where: { $0.activity == activity }) else {
      if activity == .music { self = .nowPlaying; return }
      return nil
    }
    self = tile
  }

  /// True for tiles that open a view in the island; false for one-tap actions.
  var opensInIsland: Bool { !Self.actionTiles.contains(self) }

  /// Tiles that run something (a panel, a window, a switch) instead of opening in the island.
  static let actionTiles: Set<IslandWidgetTile> = []

  /// Tiles whose view takes typing: the island becomes key while they are open and stays open
  /// until a click lands outside it, so moving the pointer away never eats a half-typed line.
  var takesKeyboard: Bool {
    switch self {
    case .termiNotch, .teleprompter, .dropClip, .notes, .obsidian, .calendar, .textCapture, .clipboard,
      .emojiPicker, .launcher, .cleaner: true
    default: false
    }
  }

  /// Tiles that read keys without a text field (terminal, prompter controls): the island takes
  /// key focus as soon as they open, instead of on the first click into a field.
  var focusesOnOpen: Bool { self == .termiNotch || self == .teleprompter || self == .emojiPicker || self == .launcher }

  /// The tiles the grid shows: the recording result only while there is one to act on.
  /// The grid's tiles. The Clipboard has its own tab in the capsule, so it is not repeated here.
  static func visible(hasRecordingResult: Bool) -> [IslandWidgetTile] {
    allCases.filter { $0 != .clipboard && ($0 != .recording || hasRecordingResult) }
  }

  /// Height the island reserves under the camera band while this widget is open (back row included).
  var openHeight: CGFloat {
    switch self {
    case .clipboard: 380
    case .share: 330
    case .calendar, .camera, .removeBackground: 306
    case .notes, .obsidian, .voiceMemo, .dictation: 316
    case .agents: 322
    case .termiNotch: 316
    case .textCapture, .teleprompter: 306
    case .audioControl, .airPlayRooms: 272
    case .dropClip: 300
    case .stats, .keepAwake, .devices, .frontApp, .recording: 262
    case .timer: 252
    case .xcodeBuilds: 206
    case .nowPlaying: 236
    case .weather: 300
    case .screenshot: 284
    case .emojiPicker, .launcher: 330
    case .cleaner: 340
    case .menuBarManager: 300
    }
  }
}

// MARK: - Icons (art lives in Icons/FeatureIconCatalog.swift)

extension IslandWidgetTile {
  var symbol: String {
    switch self {
    case .recording: "record.circle.fill"
    case .weather: "cloud.sun.fill"
    case .nowPlaying: "music.note"
    case .clipboard: "doc.on.clipboard.fill"
    case .stats: "circle"
    case .textCapture: "text.viewfinder"
    case .calendar: "calendar"
    case .removeBackground: "person.fill"
    case .timer: "timer"
    case .notes: "note.text"
    case .obsidian: "diamond.fill"
    case .audioControl: "speaker.wave.2.fill"
    case .airPlayRooms: "airplayaudio"
    case .termiNotch: "terminal.fill"
    case .teleprompter: "text.line.first.and.arrowtriangle.forward"
    case .dropClip: "text.cursor"
    case .emojiPicker: "face.smiling.inverse"
    case .xcodeBuilds: "hammer.fill"
    case .launcher: "bolt.fill"
    case .cleaner: "trash.circle.fill"
    case .menuBarManager: "menubar.rectangle"
    case .agents: "sparkles"
    case .keepAwake: "cup.and.saucer.fill"
    case .camera: "camera.fill"
    case .voiceMemo: "waveform"
    case .dictation: "mic.fill"
    case .devices: "battery.75percent"
    case .share: "dot.radiowaves.left.and.right"
    case .frontApp: "macwindow"
    case .screenshot: "camera.viewfinder"
    }
  }
}

/// A widget's icon on the Widgets grid: the real Apple icon where there is one, otherwise custom
/// art on the same grid (see `FeatureIconView`). `size` is the visible tile.
struct IslandWidgetIcon: View {
  let tile: IslandWidgetTile
  var size: CGFloat = IslandWidgetGrid.iconSize

  var body: some View {
    FeatureIconView(tile.icon, size: size)
  }
}
