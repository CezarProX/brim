import AppKit
import SwiftUI

/// Everything the tour's live demos draw from, built once per tour. The player song arrives
/// asynchronously; the rest is ready at once.
@MainActor
final class OnboardingFixtures: ObservableObject {
  @Published private(set) var sample: NowPlayingModel?
  let queue: PlayingNextModel
  let files: OnboardingSamples.TrayFiles
  let tray: FileTrayStore
  let clipboard: [ClipboardEntry]
  let commandCenter: CommandCenterStore
  let glances: IslandGlanceModel
  let cover: NSImage?

  init(sample: NowPlayingModel? = nil) {
    self.sample = sample
    queue = OnboardingSamples.queue()
    files = OnboardingSamples.makeFiles()
    tray = OnboardingSamples.trayStore(files)
    clipboard = OnboardingSamples.clipboardEntries()
    let defaults = UserDefaults(suiteName: "brim.onboarding.demo") ?? .standard
    commandCenter = CommandCenterStore(settings: AppSettings(defaults: defaults))
    glances = IslandGlanceModel(settings: AppSettings(defaults: defaults), battery: (percent: 82, charging: false))
    cover = OnboardingSamples.coverData(seed: 2, size: 640).flatMap(NSImage.init(data:))
  }

  func load() async {
    guard sample == nil else { return }
    sample = await OnboardingSamples.nowPlaying()
  }
}
