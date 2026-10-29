import AppKit
import SwiftUI

/// The tour's island pages show the app's real island (`NotchShelfView`), on models of its own fed
/// with the tour's samples (Tray, clipboard, song, download, meeting), so it looks exactly like the
/// island and the user's files, history and calendar stay out of it.
@MainActor
final class TourIslandModels: ObservableObject {
  let presentation = NotchPresentation()
  let shelf: ShelfStore
  let clipboard: ClipboardStore
  let homeWidgets = HomeWidgetStore(widgets: [.media, .clock, .timer], persist: { _ in }, scrollMode: { .automatic })
  let calls = CallActivityModel(accessibilityTrusted: { false })
  let recording = ScreenRecordingModel(probe: { nil })
  let timers = NativeTimerModel()
  let notifications: NotificationHUDModel
  let weather: WeatherStore
  /// A calendar and downloads of the tour's own, so the live page shows a sample meeting and download.
  let calendar = CalendarActivityModel()
  let downloads = DownloadProgressModel(folder: { nil })
  let center: ActivityCenter
  private var downloading: Task<Void, Never>?

  init(clipboard entries: [ClipboardEntry]) {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "brim.onboarding.island") ?? .standard)
    shelf = ShelfStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("BrimTourShelf", isDirectory: true))
    clipboard = OnboardingSamples.clipboardStore(entries)
    notifications = NotificationHUDModel(settings: settings)
    weather = WeatherStore(settings: settings)
    calendar.pinned = nil
    center = ActivityCenter(calendar: calendar, downloads: downloads)
    // A 14-inch MacBook's notch, so the island opens at the size it has on the real display.
    presentation.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 184, notchHeight: 32)
  }

  /// Puts the island in the state a page shows: the page open on, or closed for the login page.
  func show(_ page: OnboardingPage, transform urls: [URL]) {
    presentation.convertURLs = page == .transform ? urls : []
    presentation.isExpanded = page != .almostThere
    showLive(page == .live)
    switch page {
    case .welcome: presentation.navigate(to: .showing(.home))
    case .tray: presentation.navigate(to: .showing(.tray))
    case .clipboard: presentation.navigate(to: .showing(.clipboard))
    case .player, .glass: presentation.navigate(to: .showing(.music))
    case .widgets: presentation.navigate(to: .showing(.widgets))
    case .live:
      presentation.navigate(to: .showing(.home))
      presentation.selectedActivity = .download
    default: break
    }
  }

  /// The live page: a download that keeps finishing (its ring and countdown), and a meeting that
  /// starts in a few minutes, riding beside it. Off every other page, so they never show there.
  private func showLive(_ on: Bool) {
    downloading?.cancel()
    downloading = nil
    guard on else {
      presentation.selectedActivity = nil
      downloads.showPreview(nil)
      calendar.setMeeting(nil)
      return
    }
    let now = Date.now
    calendar.setMeeting(CalendarMeeting(
      id: "tour-meeting", title: "Design review", startsAt: now.addingTimeInterval(4 * 60),
      endsAt: now.addingTimeInterval(64 * 60), calendar: "Work", joinURL: nil))
    downloads.showPreview(Self.download(at: 0.2))
    downloading = Task { @MainActor [weak self] in
      var fraction = 0.2
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        fraction = fraction >= 0.98 ? 0.2 : fraction + 0.01
        self?.downloads.showPreview(Self.download(at: fraction))
      }
    }
  }

  private static func download(at fraction: Double) -> DownloadSnapshot {
    DownloadSnapshot(name: "Xcode_26.xip", bytes: Int64(fraction * 4_200_000_000), fraction: fraction,
                     secondsLeft: (1 - fraction) * 90, count: 1)
  }
}

/// The real island hanging from the top of the tour window, following the tour's page.
struct OnboardingRealIsland: View {
  let page: OnboardingPage
  @ObservedObject var models: TourIslandModels
  @ObservedObject var nowPlaying: NowPlayingModel
  @ObservedObject var fixtures: OnboardingFixtures
  @ObservedObject private var sharedTheme = IslandTheme.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Pages whose demo is the island itself, as it is in the app.
  static func shows(_ page: OnboardingPage) -> Bool {
    switch page {
    case .welcome, .tray, .transform, .clipboard, .player, .glass, .live, .widgets, .almostThere: true
    default: false
    }
  }

  /// The Liquid Glass page shows glass even when the user's island is plain black.
  private var theme: IslandTheme {
    guard page == .glass, !sharedTheme.surface.usesGlass else { return sharedTheme }
    return IslandTheme(surface: .dynamicGlass, tinted: sharedTheme.tinted)
  }

  var body: some View {
    NotchShelfView(
      presentation: models.presentation, store: models.shelf, nowPlaying: nowPlaying, calls: models.calls,
      recording: models.recording, timers: models.timers, extensions: models.center, tray: fixtures.tray, homeWidgets: models.homeWidgets,
      notifications: models.notifications, glances: fixtures.glances, theme: theme, weather: models.weather,
      playingNext: fixtures.queue, clipboard: models.clipboard)
      .frame(width: OnboardingMetrics.size.width, height: OnboardingMetrics.dotsY(rows: false) - 24, alignment: .top)
      // A demo: clicks would open real tools (Transform, AirDrop, widgets) from inside the tour.
      .allowsHitTesting(false)
      .onAppear { models.show(page, transform: [fixtures.files.photo]) }
      .onChange(of: page) { _, next in
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { models.show(next, transform: [fixtures.files.photo]) }
      }
  }
}
