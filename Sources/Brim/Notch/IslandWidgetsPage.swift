import SwiftUI

/// The Widgets page: a grid of glossy app-style tiles, four to a row. A tile opens its
/// widget inside the island with a back chevron; tiles beyond two rows sit on further pages.
@MainActor
struct IslandWidgetsPage: View {
  let opened: IslandWidgetTile?
  @ObservedObject var center: ActivityCenter
  @ObservedObject var store: ShelfStore
  @ObservedObject var nowPlaying: NowPlayingModel
  var outputs: AudioOutputModel
  @Binding var outputDrawer: Bool
  @ObservedObject var recordingResult: RecordingResultModel = .shared
  /// Fixed tiles for previews and tests; nil shows every tile that applies right now.
  var fixedTiles: [IslandWidgetTile]?
  var weather: WeatherStore = .shared
  let open: (IslandWidgetTile?) -> Void
  var onClipboardConfirmation: (Bool) -> Void = { _ in }
  @State private var page = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if let opened {
        IslandOpenedWidget(
          tile: opened, center: center, store: store, nowPlaying: nowPlaying, outputs: outputs,
          outputDrawer: $outputDrawer, weather: weather, back: { open(nil) }, open: open,
          onClipboardConfirmation: onClipboardConfirmation)
          .id(opened)
          .transition(.islandContent)
      } else {
        grid.transition(.islandContent)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var tiles: [IslandWidgetTile] {
    fixedTiles ?? IslandWidgetTile.visible(hasRecordingResult: recordingResult.result != nil)
  }

  /// Pages of two full rows stacked vertically; one scroll moves exactly one page, so a row is
  /// never left half cut at either edge.
  private var grid: some View {
    let pages = IslandWidgetGrid.pages(of: tiles)
    let height = IslandPageLayout.widgetsHeight(tiles: tiles.count)
    let current = min(page, max(0, pages.count - 1))
    return VStack(spacing: 0) {
      ForEach(pages.indices, id: \.self) { index in
        gridPage(pages[index])
          .frame(height: height, alignment: .top)
          // The page leaving fades and settles back a touch while the next one slides in, so the
          // turn reads as one clean move instead of two half-cut rows sliding past the edge.
          .opacity(index == current ? 1 : 0)
          .scaleEffect(index == current || reduceMotion ? 1 : 0.94)
          .allowsHitTesting(index == current)
          .accessibilityHidden(index != current)
      }
    }
    .offset(y: -CGFloat(current) * height)
    .frame(maxWidth: .infinity)
    .frame(height: height, alignment: .top)
    .clipped()
    .overlay(alignment: .trailing) {
      if pages.count > 1 {
        IslandWidgetPageDots(count: pages.count, current: current) { turn(to: $0, of: pages.count) }
          .padding(.trailing, 18)
      }
    }
    .background { IslandWidgetPageCatcher { turn(to: current + $0, of: pages.count) } }
  }

  private func gridPage(_ tiles: [IslandWidgetTile]) -> some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(IslandWidgetGrid.columnWidth), spacing: 0), count: IslandWidgetGrid.columns),
      spacing: IslandWidgetGrid.rowSpacing
    ) {
      ForEach(tiles) { tile in
        IslandWidgetTileButton(tile: tile, live: isLive(tile)) { activate(tile) }
      }
    }
    .padding(.top, IslandWidgetGrid.topPadding)
    .padding(.bottom, IslandWidgetGrid.bottomPadding)
  }

  private func turn(to target: Int, of count: Int) {
    let next = min(max(0, target), max(0, count - 1))
    guard next != page else { return }
    // Critically damped: the island's layout spring overshoots, which showed the neighbouring
    // page's rows bouncing in and out at the clipped edge.
    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.36)) { page = next }
  }

  private func activate(_ tile: IslandWidgetTile) {
    switch tile {
    default:
      open(tile)
    }
  }

  /// Running tools get a small live dot, like an app with something going on.
  private func isLive(_ tile: IslandWidgetTile) -> Bool {
    switch tile {
    case .nowPlaying: nowPlaying.track?.isPlaying == true
    case .timer: center.focus.isActive
    case .dictation: center.dictation.isRecording
    case .voiceMemo: VoiceRecorderModel.shared.isRecording
    case .keepAwake: KeepAwakeModel.shared.isActive
    case .menuBarManager: MenuBarManagerController.shared.isRunning
    case .agents: center.coding.session?.isLive() == true || center.agent.active != nil
    default: tile.activity.map { center.activeKinds.contains($0) } ?? false
    }
  }
}

/// One glossy icon with its name, lifting a little under the pointer.
private struct IslandWidgetTileButton: View {
  let tile: IslandWidgetTile
  var live = false
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      VStack(spacing: IslandWidgetGrid.labelGap) {
        IslandWidgetIcon(tile: tile)
          .overlay(alignment: .topTrailing) {
            if live {
              Circle().fill(Color.green).frame(width: 9, height: 9)
                .overlay { Circle().stroke(.black, lineWidth: 1.5) }
                .offset(x: 2, y: -2)
            }
          }
          .scaleEffect(hovered && !reduceMotion ? 1.06 : 1)
        Text(tile.title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(IslandInk.primary.opacity(0.92))
          .lineLimit(2).multilineTextAlignment(.center)
          .frame(width: IslandWidgetGrid.columnWidth - 6)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: IslandWidgetGrid.columnWidth, height: IslandWidgetGrid.tileHeight, alignment: .top)
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.92))
    .onHover { hovered = $0 }
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: hovered)
    .help(tile.title)
    .accessibilityLabel(tile.title)
    .accessibilityValue(live ? "Active" : "")
  }
}

/// A widget opened from the grid: back chevron and title, then the widget itself.
@MainActor
struct IslandOpenedWidget: View {
  let tile: IslandWidgetTile
  @ObservedObject var center: ActivityCenter
  @ObservedObject var store: ShelfStore
  @ObservedObject var nowPlaying: NowPlayingModel
  var outputs: AudioOutputModel
  @Binding var outputDrawer: Bool
  var weather: WeatherStore = .shared
  let back: () -> Void
  let open: (IslandWidgetTile?) -> Void
  var onClipboardConfirmation: (Bool) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      header
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(.horizontal, 28)
    .padding(.top, 8)
    .padding(.bottom, 20)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Button(action: back) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
          .foregroundStyle(IslandInk.primary)
          .frame(width: 26, height: 26)
          .background(IslandFill.raised, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.86))
      .keyboardShortcut(.cancelAction)
      .help("Back to Widgets")
      .accessibilityLabel("Back to Widgets")
      IslandWidgetIcon(tile: tile, size: 22)
      VStack(alignment: .leading, spacing: 0) {
        Text(tile.title).font(IslandFont.title).foregroundStyle(IslandInk.primary)
        if let subtitle = tile.subtitle {
          Text(subtitle).font(IslandFont.body).foregroundStyle(IslandInk.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(height: tile.subtitle == nil ? 28 : 34)
  }

  @ViewBuilder private var content: some View {
    switch tile {
    case .weather:
      WeatherAppView(store: weather)
    case .nowPlaying:
      // Opens the Music tab (see IslandNavigation.opening); nothing to draw here.
      EmptyView()
    case .clipboard:
      ClipboardLibraryView(
        store: store, onConfirmationChange: onClipboardConfirmation,
        onShare: { url in
          center.sharing.accept([url])
          open(.share)
        })
    case .removeBackground:
      RemoveBackgroundWidgetView()
    default:
      if let tool = IslandToolContent(tile: tile, close: back) {
        tool
      } else {
        activityContent
      }
    }
  }

  @ViewBuilder private var activityContent: some View {
    switch tile {
    default:
      if let activity = tile.activity {
        ScrollView {
          ExtendedActivityView(activity: activity, center: center)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
      }
    }
  }
}
