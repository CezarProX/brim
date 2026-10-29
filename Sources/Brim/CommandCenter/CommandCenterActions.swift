import AppKit

/// What each tile does when tapped. Reuses the app's existing entry points; nothing here owns state.
@MainActor
enum CommandCenterActions {
  static func perform(_ kind: TileKind) {
    switch kind {
    case .nowPlaying: NowPlayingModel.shared.playPause()
    case .clipboard: ClipboardFeature.shared.openClipboard()
    case .captureArea: CaptureCoordinator.shared.startCapture()
    case .captureWindow: Task { await captureWindow() }
    case .captureFullscreen: Task { await captureFullscreen() }
    case .recordScreen: RecordingController.shared.toggle()
    case .colorPicker: Task { await RingActionRunner.run(RingSlot(kind: .builtIn, argument: RingBuiltIn.colorPicker.rawValue)) }
    case .ocr: Task { await RingActionRunner.run(RingSlot(kind: .builtIn, argument: RingBuiltIn.grabText.rawValue)) }
    case .transform: chooseFilesToTransform()
    case .history: HistoryWindowController.showHistoryWindow(kind: .save)
    case .settings: SettingsWindowController.shared.show()
    case .cpu, .memory, .disk, .battery, .network: SettingsWindowController.shared.show(.tool(.stats))
    case .stayAwake: MacSwitches.shared.toggleStayAwake()
    case .darkMode: MacSwitches.shared.toggleDarkMode()
    case .desktopIcons: MacSwitches.shared.toggleDesktopIcons()
    case .hiddenFiles: MacSwitches.shared.toggleHiddenFiles()
    case .islandVisibility: MacSwitches.shared.toggleIslandVisibility()
    case .launcher:
      if AppSettings.shared.thunderstormEnabled { ThunderstormController.shared.toggle() } else { SettingsWindowController.shared.show(.tool(.launcher, anchor: "launcher.enable")) }
    case .cleaner: CleanerController.shared.show()
    case .menuBarManager: MenuBarManagerController.shared.toggle()
    case .upcoming: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
  }

  private static func hint(_ text: String, _ symbol: String) {
    IslandFlashCenter.shared.show(text, symbol: symbol, tint: .orange)
  }

  /// The screen under the pointer, handed to the normal save/copy flow.
  private static func captureFullscreen() async {
    do {
      let frames = try await ScreenCapturer.captureFullScreens()
      let pointer = NSEvent.mouseLocation
      let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
      guard let image = screen.flatMap({ frames[$0] }) ?? frames.values.first else { return }
      CaptureCoordinator.shared.finishWithImage(image)
    } catch {
      if case ScreenCapturer.CaptureError.permissionDenied = error {
        PermissionsHelper.showScreenRecordingRecovery()
      } else {
        NotificationCenterHelper.notify(title: "Capture Failed", body: error.localizedDescription)
      }
    }
  }

  /// The system's window picker (click a window), then the normal save/copy flow.
  private static func captureWindow() async {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("brim-window-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: file) }
    let captured: Bool = await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-i", "-w", "-x", file.path]
      process.terminationHandler = { _ in continuation.resume(returning: FileManager.default.fileExists(atPath: file.path)) }
      do { try process.run() } catch { continuation.resume(returning: false) }
    }
    guard captured, let image = NSImage(contentsOf: file) else { return }
    CaptureCoordinator.shared.finishWithImage(image)
  }

  /// Transform needs files: pick them, then the island opens its convert card.
  private static func chooseFilesToTransform() {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.message = "Choose files to transform"
    guard panel.runModal() == .OK else { return }
    NotchShelfController.shared.presentConvert(panel.urls)
  }
}
