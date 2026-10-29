import Foundation

/// One line under the title of an opened widget: what the app does, in plain words.
/// Tiles without an entry show no subtitle.
extension IslandWidgetTile {
  var subtitle: String? {
    switch self {
    case .notes: L10n.tr("Quick notes that stay on this Mac")
    case .obsidian: L10n.tr("Read and write your Obsidian vault")
    case .textCapture: L10n.tr("Copy text from anything on your screen")
    case .dictation: L10n.tr("Speak and type in any app, on this Mac")
    case .voiceMemo: L10n.tr("Record your voice and turn it into text")
    case .emojiPicker: L10n.tr("Find an emoji and drop it into the app you were using")
    case .launcher: L10n.tr("Open apps, files and answers from one search box")
    case .cleaner: L10n.tr("Remove an app along with the files it leaves behind")
    case .menuBarManager: L10n.tr("Tuck menu bar icons behind one arrow")
    case .weather: L10n.tr("Hourly and 5-day forecast for your city")
    case .calendar: L10n.tr("Your events, one-tap join and quick add")
    case .timer: L10n.tr("Focus in timed blocks, then take a short break")
    case .stats: L10n.tr("Live CPU, memory, disk and network use of this Mac")
    case .devices: L10n.tr("Battery of your Mac and connected Bluetooth accessories")
    case .keepAwake: L10n.tr("Stops your Mac and screen from going to sleep")
    case .frontApp: L10n.tr("The app you are using, and quick ways to hide, quit or switch")
    case .audioControl: L10n.tr("Set a separate volume for each app")
    case .airPlayRooms: L10n.tr("Choose where this Mac plays sound")
    case .camera: L10n.tr("Check how you look before a call")
    case .share: L10n.tr("Drop files here, then send them with AirDrop")
    case .termiNotch: L10n.tr("A real shell; commands run only when you press Return")
    case .teleprompter: L10n.tr("Read your script as it scrolls under the camera")
    case .xcodeBuilds: L10n.tr("Live Xcode build progress and the last result")
    case .agents: L10n.tr("Follow your coding agents and answer them from here")
    case .screenshot: L10n.tr("Drag over anything on screen, then copy, save or mark it up")
    case .dropClip: L10n.tr("Select text in any app for a bar of quick actions")
    default: nil
    }
  }
}
