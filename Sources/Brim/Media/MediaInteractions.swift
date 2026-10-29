import AppKit

/// Click on the notch while music plays, per the "What opens" setting.
@MainActor
enum NotchMusicClick {
  /// Returns true when the click was consumed here; false means the caller should open the island as usual.
  static func handle(action: NotchMusicClickAction? = nil, model: NowPlayingModel? = nil) -> Bool {
    let action = action ?? AppSettings.shared.notchMusicClickAction
    let model = model ?? NowPlayingModel.shared
    guard let track = model.track, track.isPlaying else { return false }
    switch action {
    case .openIsland: return false
    case .playPause:
      _ = model.command(.playPause)
      return true
    case .openMusicApp:
      let bundle = track.snapshot.source.bundleID
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return false }
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      return true
    }
  }
}

/// Space toggles play/pause while the open island has keyboard focus and no text field is editing.
@MainActor
final class IslandSpacebarMonitor {
  static let shared = IslandSpacebarMonitor()
  private var monitor: Any?
  /// Set by the shell: true while the island is open.
  var isIslandOpen: () -> Bool = { false }

  nonisolated static let spaceKeyCode: UInt16 = 49

  /// Pure rule, shared with tests.
  nonisolated static func shouldHandle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, enabled: Bool, islandOpen: Bool,
                           editingText: Bool, hasTrack: Bool) -> Bool {
    keyCode == spaceKeyCode && modifiers.intersection([.command, .option, .control, .shift]).isEmpty
      && enabled && islandOpen && !editingText && hasTrack
  }

  func start() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      let editing = event.window?.firstResponder is NSText
      let handle = MainActor.assumeIsolated {
        Self.shouldHandle(
          keyCode: event.keyCode, modifiers: event.modifierFlags, enabled: AppSettings.shared.mediaSpacebarPlayPause,
          islandOpen: self.isIslandOpen(), editingText: editing, hasTrack: NowPlayingModel.shared.track != nil)
      }
      guard handle else { return event }
      MainActor.assumeIsolated { _ = NowPlayingModel.shared.command(.playPause) }
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
