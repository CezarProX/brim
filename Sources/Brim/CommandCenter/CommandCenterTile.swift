import SwiftUI

/// How much of a page's grid one tile covers: small 1x1, wide 2x1, hero 2x2.
enum TileSize: String, CaseIterable, Sendable {
  case small, wide, hero

  var columns: Int { self == .small ? 1 : 2 }
  var rows: Int { self == .hero ? 2 : 1 }
  var title: String { rawValue.capitalized }
}

/// Every tile the Command Center can show. Raw values are stable ids stored in the layout string.
enum TileKind: String, CaseIterable, Identifiable, Sendable {
  case nowPlaying = "media.nowPlaying"
  case clipboard = "action.clipboard"
  case captureArea = "action.capture.area"
  case captureWindow = "action.capture.window"
  case captureFullscreen = "action.capture.fullscreen"
  case colorPicker = "action.colorPicker"
  case ocr = "action.ocr"
  case transform = "action.transform"
  case history = "action.history"
  case settings = "action.settings"
  case stayAwake = "toggle.stayAwake"
  case darkMode = "toggle.darkMode"
  case desktopIcons = "toggle.desktopIcons"
  case hiddenFiles = "toggle.hiddenFiles"
  case islandVisibility = "toggle.notchVisibility"
  case cpu = "stats.cpu"
  case memory = "stats.memory"
  case disk = "stats.disk"
  case battery = "stats.battery"
  case network = "stats.network"
  case upcoming = "widget.upcoming"
  case launcher = "action.launcher"
  case cleaner = "action.cleaner"
  case menuBarManager = "toggle.menuBarManager"
  case recordScreen = "action.record.screen"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .nowPlaying: "Now Playing"
    case .clipboard: "Clipboard"
    case .captureArea: "Capture Area"
    case .captureWindow: "Capture Window"
    case .captureFullscreen: "Capture Screen"
    case .colorPicker: "Pick Color"
    case .ocr: "Grab Text"
    case .transform: "Transform"
    case .history: "Screenshots"
    case .settings: "Settings"
    case .stayAwake: "Keep Awake"
    case .darkMode: "Dark Mode"
    case .desktopIcons: "Desktop Icons"
    case .hiddenFiles: "Hidden Files"
    case .islandVisibility: "Island"
    case .cpu: "CPU"
    case .memory: "Memory"
    case .disk: "Disk"
    case .battery: "Battery"
    case .network: "Network"
    case .upcoming: "Up Next"
    case .launcher: "Launcher"
    case .cleaner: "Cleaner"
    case .menuBarManager: "Menu Bar"
    case .recordScreen: "Record Screen"
    }
  }

  /// The label for a small tile, which only has room for one short word.
  var shortTitle: String {
    switch self {
    case .captureArea: "Area"
    case .captureWindow: "Window"
    case .captureFullscreen: "Screen"
    case .recordScreen: "Record"
    case .desktopIcons: "Hide Desktop"
    case .islandVisibility: "Island"
    case .stayAwake: "Awake"
    default: title
    }
  }

  var symbol: String {
    switch self {
    case .nowPlaying: "music.note"
    case .clipboard: "list.clipboard"
    case .captureArea: "rectangle.dashed"
    case .captureWindow: "macwindow"
    case .captureFullscreen: "display"
    case .colorPicker: "eyedropper"
    case .ocr: "text.viewfinder"
    case .transform: "wand.and.stars"
    case .history: "photo.on.rectangle"
    case .settings: "gearshape"
    case .stayAwake: "cup.and.saucer.fill"
    case .darkMode: "circle.lefthalf.filled"
    case .desktopIcons: "desktopcomputer"
    case .hiddenFiles: "eye"
    case .islandVisibility: "rectangle.topthird.inset.filled"
    case .cpu: "cpu"
    case .memory: "memorychip"
    case .disk: "internaldrive"
    case .battery: "battery.75percent"
    case .network: "arrow.up.arrow.down"
    case .upcoming: "calendar"
    case .launcher: "magnifyingglass"
    case .cleaner: "trash"
    case .menuBarManager: "menubar.arrow.up.rectangle"
    case .recordScreen: "record.circle"
    }
  }

  var tint: Color {
    switch self {
    case .nowPlaying: .pink
    case .clipboard: .orange
    case .captureArea, .captureWindow, .captureFullscreen: .blue
    case .colorPicker: .pink
    case .ocr: .teal
    case .transform: .purple
    case .history: .indigo
    case .settings: .gray
    case .stayAwake: .yellow
    case .darkMode: .indigo
    case .desktopIcons: .cyan
    case .hiddenFiles: .mint
    case .islandVisibility: .purple
    case .cpu: .teal
    case .memory: .purple
    case .disk: .orange
    case .battery: .green
    case .network: .blue
    case .upcoming: .red
    case .launcher: .indigo
    case .cleaner: .red
    case .menuBarManager: .purple
    case .recordScreen: .red
    }
  }

  var isToggle: Bool {
    switch self {
    case .stayAwake, .darkMode, .desktopIcons, .hiddenFiles, .islandVisibility, .menuBarManager: true
    default: false
    }
  }

  var isStat: Bool {
    switch self {
    case .cpu, .memory, .disk, .battery, .network: true
    default: false
    }
  }

  /// Sizes the tile looks right at, first being the default.
  var allowedSizes: [TileSize] {
    switch self {
    case .nowPlaying: [.hero, .wide]
    case .upcoming: [.wide, .hero]
    case .cpu, .memory, .disk, .battery, .network: [.small, .wide]
    default: [.small, .wide]
    }
  }

  var defaultSize: TileSize { allowedSizes[0] }

  /// Words the add-tile picker groups by.
  var group: String {
    if isToggle { return "Switches" }
    if isStat { return "Stats" }
    switch self {
    case .nowPlaying, .upcoming: return "Widgets"
    default: return "Actions"
    }
  }

  /// Switches and media controls act in place; the popover stays open for them.
  var closesAfterAction: Bool { !(isToggle || isStat || self == .nowPlaying || self == .upcoming) }
}

/// One tile in the layout: which tile, at what size.
struct TilePlacement: Equatable, Identifiable, Sendable {
  let kind: TileKind
  var size: TileSize
  var id: String { kind.rawValue }

  init(_ kind: TileKind, _ size: TileSize? = nil) {
    self.kind = kind
    self.size = size.flatMap { kind.allowedSizes.contains($0) ? $0 : nil } ?? kind.defaultSize
  }
}
