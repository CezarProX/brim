import SwiftUI

/// The views the feature packages built for the Widgets page, each opened inside the island under
/// the back chevron: productivity (calendar, Pomodoro, notes), audio, droplets and the recording result.
@MainActor
struct IslandToolContent: View {
  let tile: IslandWidgetTile
  /// Leaves the opened tool (the recording card's close button).
  let close: () -> Void

  /// nil for tiles that show something else (a live activity's view, the clipboard, weather…).
  init?(tile: IslandWidgetTile, close: @escaping () -> Void) {
    guard Self.handles(tile) else { return nil }
    self.tile = tile
    self.close = close
  }

  static func handles(_ tile: IslandWidgetTile) -> Bool {
    switch tile {
    case .calendar, .timer, .notes, .obsidian, .textCapture, .audioControl, .airPlayRooms, .termiNotch,
      .teleprompter, .dropClip, .xcodeBuilds, .recording, .screenshot, .emojiPicker, .launcher, .cleaner, .menuBarManager:
      true
    default:
      false
    }
  }

  var body: some View {
    switch tile {
    case .calendar: CalendarPageView(model: ActivityCenter.shared.calendar)
    case .timer: PomodoroPanelView()
    case .notes: NotesPanelView(mode: .notes)
    case .obsidian: NotesPanelView(mode: .obsidian)
    case .textCapture: TextCaptureIslandView()
    case .audioControl: AudioControlView(showsTitle: false)
    case .airPlayRooms: AirPlayRoomPanel().padding(.horizontal, -IslandSpace.l)
    case .termiNotch: TermiNotchIslandView()
    case .teleprompter: TeleprompterIslandView()
    case .dropClip: DropClipIslandView()
    case .xcodeBuilds: XcodeBuildCard(model: .shared).frame(maxWidth: .infinity, alignment: .leading)
    case .screenshot: ScreenshotIslandView()
    case .recording: RecordingResultTool(model: .shared, close: close)
    case .emojiPicker: EmojiIslandView()
    case .launcher: LauncherIslandView()
    case .cleaner: CleanerIslandHost()
    case .menuBarManager: MenuBarIslandView()
    default: EmptyView()
    }
  }
}

/// The last recording's card; leaves the tool once the card is dismissed.
private struct RecordingResultTool: View {
  @ObservedObject var model: RecordingResultModel
  let close: () -> Void

  var body: some View {
    RecordingResultCardHost(model: model)
      .onChange(of: model.result == nil) { _, gone in if gone { close() } }
  }
}
