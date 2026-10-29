import SwiftUI

/// The open island's pages (Home, Clipboard, Tray, Music, Widgets, Messages): which one shows, how big it is, and its content.
extension NotchShelfView {
  var page: IslandPage { presentation.navigation.page }
  var openedWidget: IslandWidgetTile? { presentation.navigation.openedWidget }

  /// Home is the widget shelf (its Media widget is the small player); a live activity's card
  /// takes its place while one leads or was picked. The full player lives on the Music page.
  var isShelfHome: Bool {
    guard page == .home, presentation.selectedActivity == nil || presentation.selectedActivity == .music
        || presentation.selectedActivity?.isPassiveStatus == true
    else { return false }
    return Self.showsShelf(homeTapped: presentation.homeTapped, editing: homeWidgets.isEditing, primary: selectedActivity)
  }

  /// - Returns: true for the widget shelf, false for the leading activity's card.
  nonisolated static func showsShelf(homeTapped: Bool, editing: Bool, primary: IslandActivity?) -> Bool {
    editing || homeTapped || primary == nil || primary == .music || primary?.isPassiveStatus == true
  }

  /// The Music page: the full player, or the idle "Not playing" card when no track is known.
  var isMusicHome: Bool { page == .music }

  var isStatusHome: Bool {
    page == .home && !isShelfHome && (selectedActivity == .recording || selectedActivity == .timer)
  }

  /// Clearance above the player card: under the camera on a notched Mac, a small margin on the pill.
  var musicTopInset: CGFloat {
    presentation.geometry.isFloating ? 20 : max(45, presentation.geometry.notchHeight + 13)
  }

  /// The Home player card's size, Playing Next column included when the source has a queue.
  var musicCardSize: CGSize {
    let side = MusicPlayerCard.showsSidePanel(
      queueOpen: musicQueueOpen, queueAvailable: QueueCapability.supportsQueue(nowPlaying.track?.snapshot.source),
      lyricsOpen: musicLyricsOpen, outputsOpen: presentation.isPresentingAudioOutputs)
    return MusicPlayerCard.preferredSize(showsQueue: side, topInset: musicTopInset)
  }

  var isDropMode: Bool {
    presentation.isShowingDropTargets || !presentation.convertURLs.isEmpty || !presentation.localSendURLs.isEmpty
  }

  var preferredWidth: CGFloat? {
    if !presentation.convertURLs.isEmpty { return TransformPanelView.preferredWidth }
    if !presentation.localSendURLs.isEmpty { return IslandPageLayout.widgetsWidth }
    if presentation.isShowingDropTargets { return 420 }
    if isMusicHome { return musicCardSize.width + 2 * shoulderInset }
    switch page {
    case .music: return musicCardSize.width + 2 * shoulderInset
    case .tray, .messages: return IslandPageLayout.trayWidth
    case .clipboard, .widgets: return IslandPageLayout.widgetsWidth
    // Exact: the widget grid, its side padding (and edit margins), and the shape's shoulders. It stays
    // under NotchGeometry's 740 pt cap at every layout (HomeWidgetGridTests), so no card is ever cut.
    case .home: return isShelfHome ? homeWidgets.shelfWidth + 2 * shoulderInset : nil
    }
  }

  /// Width the open shape's shoulders take on each side; the floating pill has none.
  var shoulderInset: CGFloat {
    presentation.geometry.isFloating ? 0 : IslandPageLayout.openShoulder
  }

  var utilityContentHeight: CGFloat? {
    if !presentation.convertURLs.isEmpty { return transformPanelHeight ?? TransformPanelView.preferredHeight }
    if !presentation.localSendURLs.isEmpty { return 236 }
    if presentation.isShowingDropTargets { return 112 }
    if isMusicHome {
      return max(0, musicCardSize.height - max(presentation.geometry.notchHeight, 12))
    }
    switch page {
    case .music: return max(0, musicCardSize.height - max(presentation.geometry.notchHeight, 12))
    case .tray: return IslandPageLayout.trayHeight(count: tray.items.count)
    case .clipboard: return IslandPageLayout.clipboardHeight
    case .messages: return notifications.inboxPageHeight
    case .widgets:
      if openedWidget == .agents {
        // IslandOpenedWidget's chrome: 8 top, 34 back row with subtitle, 8 gap, 20 bottom.
        return AgentsHubHeightKey.pageHeight(content: agentsHubHeight, chrome: 70, cap: IslandWidgetTile.agents.openHeight)
      }
      return openedWidget?.openHeight ?? IslandPageLayout.widgetsHeight(tiles: IslandWidgetTile.allCases.count)
    case .home:
      if isShelfHome {
        return homeWidgets.shelfHeight
      }
      if isStatusHome { return nil }
      if selectedActivity == .agent {
        // contentInsets for an activity page: 10 under the band (18 when floating), 22 at the bottom.
        return AgentsHubHeightKey.pageHeight(content: agentsHubHeight, chrome: 36, cap: 250)
      }
      return selectedActivity == .call ? 232 : 250
    }
  }

  /// Insets around the page content inside the shell.
  func contentInsets(_ geometry: NotchGeometry) -> EdgeInsets {
    let band = geometry.isFloating ? 0 : max(geometry.notchHeight, 12)
    if isNotificationOpen {
      return EdgeInsets(top: geometry.isFloating ? 6 : max(geometry.notchHeight, 12), leading: 0, bottom: 0, trailing: 0)
    }
    if !presentation.localSendURLs.isEmpty {
      return EdgeInsets(top: geometry.isFloating ? 16 : band + 8, leading: 22, bottom: 16, trailing: 22)
    }
    if !presentation.convertURLs.isEmpty {
      // The Transform header sits beside the camera, in the notch band.
      return EdgeInsets(top: geometry.isFloating ? 16 : 8, leading: 22, bottom: 18, trailing: 22)
    }
    if isMusicHome { return EdgeInsets(top: 0, leading: shoulderInset, bottom: 0, trailing: shoulderInset) }
    if !isDropMode && (page == .tray || (page == .widgets && openedWidget == nil)) {
      return EdgeInsets(top: geometry.isFloating ? 4 : band, leading: 0, bottom: 0, trailing: 0)
    }
    if page == .widgets || page == .clipboard || page == .messages {
      return EdgeInsets(top: geometry.isFloating ? 10 : band, leading: 0, bottom: 0, trailing: 0)
    }
    let side = isShelfHome ? HomeWidgetStore.horizontalPadding / 2 + shoulderInset : 28
    return EdgeInsets(top: geometry.isFloating ? 18 : band + 10, leading: side, bottom: 22, trailing: side)
  }

  // MARK: Content

  @ViewBuilder var pageContent: some View {
    switch page {
    case .tray:
      FileTrayView(store: tray, selection: initialTraySelection)
    case .clipboard:
      ClipboardLibraryView(
        store: store, clipboard: clipboard, onConfirmationChange: { presentation.isPresentingLibraryConfirmation = $0 },
        onShare: { url in
          extensions.sharing.accept([url])
          openWidget(.share)
        })
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .transition(.islandContent)
    case .widgets:
      IslandWidgetsPage(
        opened: openedWidget, center: extensions, store: store, nowPlaying: nowPlaying, outputs: outputs,
        outputDrawer: $presentation.isPresentingAudioOutputs, weather: weather, open: openWidget,
        onClipboardConfirmation: { presentation.isPresentingLibraryConfirmation = $0 })
    case .music:
      // The idle card and the player share a footprint; they cross-fade as music starts or stops.
      musicPage
        .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: nowPlaying.track == nil)
    case .home:
      homePage
    case .messages:
      NotificationInboxHost(model: notifications)
        .transition(.islandContent)
    }
  }

  @ViewBuilder var musicPage: some View {
    if nowPlaying.track != nil {
      MusicPlayerCard(
        model: nowPlaying, queue: playingNext, outputs: outputs, topInset: musicTopInset, showsQueue: $musicQueueOpen,
        showsLyrics: $musicLyricsOpen,
        showsOutputs: $presentation.isPresentingAudioOutputs
      )
      .transition(.opacity)
    } else {
      HomeIdlePlayerCard(model: nowPlaying)
        .padding(EdgeInsets(top: musicTopInset, leading: 20, bottom: 20, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }
  }

  @ViewBuilder var homePage: some View {
    if isShelfHome {
      shelf.transition(.opacity)
    } else if selectedActivity == .recording {
      ScreenRecordingActivityView(model: recording, namespace: activityNamespace)
    } else if selectedActivity == .timer, let timer = timers.activeTimer {
      NativeTimerActivityView(timer: timer, model: timers)
    } else if selectedActivity == .call {
      CallActivityView(
        model: calls, embedded: true,
        onConfirmationChange: { presentation.isPresentingCallConfirmation = $0 })
    } else if let selectedActivity, ![IslandActivity.music, .call, .recording, .timer].contains(selectedActivity) {
      ScrollView {
        ExtendedActivityView(activity: selectedActivity, center: extensions)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .scrollIndicators(.hidden)
    } else {
      shelf
    }
  }

  private var shelf: some View {
    IslandWidgetShelf(
      layout: homeWidgets, center: extensions, store: store, nowPlaying: nowPlaying,
      openTool: openTool, showShelf: { openWidget(.clipboard) })
  }

  // MARK: Navigation

  func setPage(_ destination: IslandPage) {
    guard destination != page || presentation.selectedActivity != nil || destination == .home || openedWidget != nil
    else { return }
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      presentation.navigate(to: .showing(destination))
    }
  }

  /// Opens a widget on the Widgets page (nil goes back to the grid).
  func openWidget(_ widget: IslandWidgetTile?) {
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      presentation.navigate(to: .opening(widget))
    }
  }

  /// The tabs the capsule shows and the swipe walks.
  var visiblePages: [IslandPage] {
    IslandPageOrder.visible(trayCount: tray.items.count, current: page, messageCount: notifications.inbox.conversations.count)
  }

  /// Two-finger swipe: move to the neighbouring page (Home, Clipboard, Tray, Widgets).
  func stepPage(_ delta: Int) {
    if let next = IslandPageOrder.page(from: page, delta: delta, in: visiblePages) { setPage(next) }
  }

  func openTool(_ activity: IslandActivity?) {
    openWidget(activity.flatMap(IslandWidgetTile.init(activity:)))
  }

  func selectActivity(_ activity: IslandActivity) {
    // The song opens the Music page; every other activity shows its card on Home.
    guard activity != .music else { setPage(.music); return }
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      presentation.navigate(to: .showing(.home))
      presentation.homeTapped = false
      presentation.selectedActivity = activity
    }
  }
}
