import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every display uses an edge-attached notch with rounded bottom corners.
struct NotchSurfaceShape: Shape {
  var expansion: CGFloat
  var floating = false
  /// Height of the closed notch; the closed radii are derived from it.
  var closedHeight: CGFloat = 32

  var animatableData: CGFloat {
    get { expansion }
    set { expansion = newValue }
  }

  func path(in rect: CGRect) -> Path {
    if floating {
      // Island corners: closed radius 18, open 44.
      let radius = min(rect.height / 2, 18 + max(0, min(1, expansion)) * 26)
      return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
    let t = max(0, min(1, expansion))
    // Closed radii: top clamp(round(0.24h), 8, 10), bottom clamp(round(0.32h), 11, 13); open shelf bottom 40.
    let closedTop = min(10, max(8, (0.24 * closedHeight).rounded()))
    let closedBottom = min(13, max(11, (0.32 * closedHeight).rounded()))
    let shoulder = closedTop + t * (12 - closedTop)
    let radius = min(rect.height / 2, closedBottom + t * (40 - closedBottom))
    let left = rect.minX + shoulder
    let right = rect.maxX - shoulder
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: right, y: rect.minY + shoulder), control: CGPoint(x: right, y: rect.minY))
    path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: right - radius, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
    path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: left, y: rect.maxY - radius), control: CGPoint(x: left, y: rect.maxY))
    path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

@MainActor
struct NotchShelfView: View {
  @ObservedObject var presentation: NotchPresentation
  @ObservedObject var store: ShelfStore
  @ObservedObject var nowPlaying: NowPlayingModel = .shared
  @ObservedObject var calls: CallActivityModel = .shared
  @ObservedObject var recording: ScreenRecordingModel = .shared
  @ObservedObject var timers: NativeTimerModel = .shared
  @ObservedObject var extensions: ActivityCenter = .shared
  var outputs: AudioOutputModel = .shared
  @ObservedObject var tray: FileTrayStore = .shared
  @ObservedObject var homeWidgets: HomeWidgetStore = .shared
  @ObservedObject var notifications: NotificationHUDModel = .shared
  @ObservedObject var glances: IslandGlanceModel = .shared
  @ObservedObject var theme: IslandTheme = .shared
  @ObservedObject var updater: AppUpdater = .shared
  var weather: WeatherStore = .shared
  var playingNext: PlayingNextModel = .shared
  /// Files picked when the Tray first shows (render tests use it; the island starts with none).
  var initialTraySelection: Set<UUID> = []
  /// The Clipboard page's history; nil is the real one (the first-run tour passes samples).
  var clipboard: ClipboardStore?
  private var glass: Bool { theme.effectiveSurface.usesGlass }
  @State private var dropTargeted = false
  /// Playing Next column beside the Home player (open by default).
  @State var musicQueueOpen = true
  @State var musicLyricsOpen = false
  /// What the open Transform panel asked for; nil while it is closed.
  @State var transformPanelHeight: CGFloat?
  /// The Agents hub's measured height while it is on screen (see AgentsHubHeightKey).
  @State var agentsHubHeight: CGFloat?
  @Namespace var activityNamespace
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var activities: IslandActivities {
    IslandActivities(
      recording: recording.activeRecording != nil, call: calls.activeCall != nil,
      music: nowPlaying.isInIsland() && !presentation.mediaHidden, timer: timers.activeTimer != nil,
      agentNeedsInput: extensions.coding.sessions.contains { $0.needsAttention && $0.isLive() },
      additional: extensions.activeKinds.filter { !presentation.hudElsewhere || $0 != .system },
      leader: presentation.leader)
  }

  /// What the closed island shows: see `CompactRoute` for the priority order.
  private var route: CompactRoute {
    CompactRoute.resolve(
      activities: activities, flash: presentation.hudElsewhere ? nil : extensions.flashes.current,
      hasNotification: notifications.current != nil)
  }

  var isNotificationOpen: Bool { presentation.expandedForNotification && notifications.current != nil }

  /// What the compact notification prints beside its icon; the closed island is sized from it.
  private var notificationLabelWidth: CGFloat {
    guard let item = notifications.current else { return 0 }
    return NotificationCompactView.labelWidth(
      item, overflow: notifications.overflow, floating: presentation.geometry.isFloating)
  }

  /// Song text beside the compact artwork, where Settings allows one (notch: "Notch track title";
  /// notchless: Keep song / artist name visible). Hidden while a second activity shares the notch.
  private var compactTitle: String? {
    guard route == .activity(.music), activities.secondary == nil, let track = nowPlaying.track else { return nil }
    return CompactTitlePolicy.text(
      hasNotch: !presentation.geometry.isFloating, title: track.title, artist: track.artist, settings: .shared)
  }
  var selectedActivity: IslandActivity? {
    activities.selected(presentation.selectedActivity)
  }
  /// What the island shows right now; the bubbles carry everything else.
  private var islandOwner: IslandActivity? {
    activities.islandOwner(expanded: presentation.isExpanded, selected: presentation.selectedActivity,
                           showingMusic: presentation.isShowingMusic)
  }
  private var visibleCompanion: IslandActivity? { activities.companion(to: islandOwner) }
  /// The activities riding in bubbles beside the island (or beside the open card), best first.
  private var visibleCompanions: [IslandActivity] {
    activities.companions(to: islandOwner)
  }

  /// Compute the visible size from this render's selected content. Published hover
  /// geometry catches up through observers, but must never size an initial frame
  /// using the previous card's layout.
  var layoutGeometry: NotchGeometry {
    var geometry = presentation.geometry
    // The music player card sizes itself through preferredWidth / utilityContentHeight.
    geometry.compactMusicLayout = false
    geometry.compactStatusLayout = isStatusHome
    geometry.utilityContentHeight = utilityContentHeight
    geometry.preferredWidth = preferredWidth
    geometry.musicSummaryHeight = 0
    geometry.route = route
    geometry.glanceLeft = glances.reservedWidth(.left)
    geometry.glanceRight = glances.reservedWidth(.right)
    geometry.compactTitleWidth = compactTitle == nil ? 0 : 96
    geometry.compactLabelWidth = notificationLabelWidth
    geometry.notificationBodyHeight = isNotificationOpen ? notifications.cardBodyHeight : nil
    return geometry
  }

  var body: some View {
    let geometry = layoutGeometry
    let expanded = presentation.isExpanded
    VStack(spacing: IslandNavigationLayout.gap) {
      shell(geometry: geometry, expanded: expanded)
      if expanded && !isDropMode && !isNotificationOpen && geometry.showsNavigation {
        IslandNavigationCapsule(
          page: page, trayCount: tray.items.count, unreadCount: notifications.inbox.unreadTotal,
          pages: visiblePages,
          favorites: geometry.tuning.favorites, highlight: theme.highlight,
          updateAvailable: updater.availableVersion != nil, onUpdate: openUpdateDialog,
          openFavorite: openWidget, select: setPage) { optionsMenu }
          .transition(.islandCapsule)
          .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            presentation.capsuleFrameInWindow = frame
            if abs((presentation.geometry.navigationWidth ?? 0) - frame.width) > 0.5 {
              presentation.geometry.navigationWidth = frame.width
            }
          }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundStyle(.white)
    .onPreferenceChange(TransformPanelHeightKey.self) { height in
      withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { transformPanelHeight = height }
    }
    .onPreferenceChange(AgentsHubHeightKey.self) { height in
      guard abs((height ?? 0) - (agentsHubHeight ?? 0)) > 3 else { return }
      withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { agentsHubHeight = height }
    }
    .onDrop(of: FileDropLoader.types, isTargeted: $dropTargeted) { providers in
      let placement = AppSettings.shared.trayPlacement
      switch TrayRouting.islandDrop(placement) {
      case .notchTray:
        guard tray.drop(providers) else { return false }
      case .floatingTray:
        guard FileDropLoader.load(providers, completion: { FloatingBasketController.shared.receive($0) })
        else { return false }
      }
      ShellHaptics.tick()
      if TrayRouting.opensIslandAfterDrop(placement: placement, openAfterDrop: AppSettings.shared.trayOpenAfterDrop) {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
          presentation.navigate(to: .showing(.tray))
        }
      }
      return true
    }
    .preferredColorScheme(.dark)
    .tint(theme.highlight)
    .onAppear { presentation.stepPage = { stepPage($0) } }
    .onChange(of: activities, initial: true) { _, next in
      presentation.updateActivities(next, route: route)
    }
    .onChange(of: route, initial: true) { _, next in
      presentation.updateActivities(activities, route: next)
    }
    .onChange(of: glances.reservedWidth(.left), initial: true) { _, width in
      presentation.geometry.glanceLeft = width
    }
    .onChange(of: glances.reservedWidth(.right), initial: true) { _, width in
      presentation.geometry.glanceRight = width
    }
    .onChange(of: layoutGeometry.compactTitleWidth, initial: true) { _, width in
      presentation.geometry.compactTitleWidth = width
    }
    .onChange(of: notificationLabelWidth, initial: true) { _, width in
      presentation.geometry.compactLabelWidth = width
    }
    .onChange(of: layoutGeometry.notificationBodyHeight, initial: true) { _, height in
      presentation.geometry.notificationBodyHeight = height
    }
    .onChange(of: visibleCompanion, initial: true) { _, companion in
      presentation.geometry.secondaryActivity = companion
    }
    .onChange(of: visibleCompanions, initial: true) { _, companions in
      presentation.setBubbles(companions, route: route)
    }
    .onChange(of: isMusicHome, initial: true) { _, _ in
      presentation.geometry.compactMusicLayout = false
    }

    .onChange(of: isStatusHome, initial: true) { _, statusHome in
      presentation.geometry.compactStatusLayout = statusHome
    }
    .onChange(of: presentation.isPresentingAudioOutputs) { _, visible in
      presentation.geometry.audioDrawerExpanded = visible
    }
    .onChange(of: preferredWidth, initial: true) { _, width in
      presentation.geometry.preferredWidth = width
    }
    .onChange(of: utilityContentHeight, initial: true) { _, height in
      presentation.geometry.utilityContentHeight = height
      presentation.geometry.musicSummaryHeight = 0
    }
    .confirmationDialog(
      "Clear recent screenshots?", isPresented: $presentation.isPresentingConfirmation
    ) {
      Button("Clear Screenshots", role: .destructive) { store.clear() }
    } message: {
      Text("This removes Brim’s cached copies. Files you saved elsewhere are kept.")
    }
  }

  private func shell(geometry: NotchGeometry, expanded: Bool) -> some View {
    let surfaceWidth = expanded ? geometry.expandedSize.width : geometry.collapsedSize.width
    let surfaceHeight = expanded ? geometry.expandedSize.height : geometry.collapsedSize.height
    // One surface morphs throughout the transition. Content keeps its final
    // layout size, so text and controls never squeeze into the collapsed width.
    let scale = geometry.effectiveOpenScale
    let natural = geometry.naturalExpandedSize
    return ZStack(alignment: .top) {
      DynamicGlassShellBackdrop(
        // One backdrop for both states: it turns itself solid black when closed.
        style: theme.effectiveSurface,
        level: theme.glassLevel, tinted: theme.tinted, expanded: expanded,
        solidHeight: geometry.isFloating ? 0 : (max(geometry.notchHeight, 12) + 6) * scale,
        clarity: theme.clarity, light: theme.usesLightGlass, windowTint: theme.windowTint)
      .modifier(ShellGlassMasking(mask: ShellGlassMask(
        size: CGSize(width: surfaceWidth, height: surfaceHeight), expansion: shapeExpansion(expanded, geometry),
        floating: geometry.isFloating, closedHeight: geometry.notchHeight)))
      if expanded {
        expandedContent
          .padding(contentInsets(geometry))
          .frame(width: natural.width, height: natural.height, alignment: .top)
          .scaleEffect(scale, anchor: .top)
          .frame(width: geometry.expandedSize.width, height: geometry.expandedSize.height, alignment: .top)
          .offset(x: presentation.pageDrag)
          .transition(.islandContent)
      } else {
        compactContent
          .frame(width: geometry.collapsedSize.width, height: geometry.collapsedSize.height)
          .transition(.islandCompact)
      }
    }
    .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
    .clipShape(NotchSurfaceShape(expansion: shapeExpansion(expanded, geometry), floating: geometry.isFloating, closedHeight: geometry.notchHeight))
    .background(alignment: .top) {
      if expanded && theme.showsProgressiveBlur {
        ProgressiveBlurHalo(size: CGSize(width: surfaceWidth, height: surfaceHeight), floating: geometry.isFloating)
          .transition(.islandHalo)
      }
    }
    .overlay {
      if glass {
        // A faint rim where the glass meets the wallpaper. It stays mounted and fades, so it morphs
        // with the shell: inserted on open, it would land at the final size ahead of the shell.
        NotchSurfaceShape(
          expansion: shapeExpansion(expanded, geometry), floating: geometry.isFloating,
          closedHeight: geometry.notchHeight)
          .stroke(
            LinearGradient(
              colors: [.clear, .white.opacity(0.18)], startPoint: .top, endPoint: .bottom),
            lineWidth: 0.75)
          .opacity(expanded ? 1 : 0)
      }
      if geometry.isSimulatedNotch && !(expanded && glass) {
        // External displays have no physical cutout and often use a
        // black menu bar. A hairline edge keeps the attached notch
        // visible without turning it back into a floating capsule.
        NotchSurfaceShape(expansion: expanded ? 1 : 0, floating: false)
          .stroke(.white.opacity(expanded ? 0.08 : 0.14), lineWidth: 0.75)
      }
    }
    .overlay(alignment: .topLeading) { bubble(.leading, geometry: geometry) }
    .overlay(alignment: .topTrailing) { bubble(.trailing, geometry: geometry) }
    .overlay(alignment: .top) { if !expanded { pillGlances(geometry) } }
    .offset(x: expanded ? 0 : geometry.collapsedMainOffset)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: activities)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: route)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: glances.reservedWidth(.left) + glances.reservedWidth(.right))
    .animation(NotchMotion.expansion(presentation.geometry.hudHovered, reduceMotion: reduceMotion), value: presentation.geometry.hudHovered)
    .animation(
      expanded ? NotchMotion.layout(reduceMotion: reduceMotion) : nil, value: geometry.expandedSize
    )
  }

  @ViewBuilder
  private var expandedContent: some View {
    if isNotificationOpen {
      NotificationHUDHost(model: notifications)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.islandContent)
    } else if !presentation.convertURLs.isEmpty {
      ConvertCard(urls: presentation.convertURLs) {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { presentation.convertURLs = [] }
      }
      .transition(.islandContent)
    } else if !presentation.localSendURLs.isEmpty {
      LocalSendView(model: .shared, files: presentation.localSendURLs) {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { presentation.localSendURLs = [] }
      }
      .transition(.islandContent)
    } else if presentation.isShowingDropTargets {
      QuickActionTilesRow(transform: { urls in
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
          presentation.isShowingDropTargets = false
          presentation.convertURLs = urls
        }
      })
      .transition(.islandContent)
    } else {
      pageContent
        .transition(.islandContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  @ViewBuilder
  var optionsMenu: some View {
    Button("Take a screenshot") { CaptureCoordinator.shared.startCapture() }
    Button("Customize Home…") {
      withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
        // Not setPage: on Home that would flip between the player and the widgets.
        if page != .home || presentation.selectedActivity != nil { presentation.navigate(to: .showing(.home)) }
        homeWidgets.isEditing = true
      }
    }
    if activities.available.count > 1 {
      Menu("Live activities") {
        ForEach(activities.available, id: \.self) { activity in
          Button {
            selectActivity(activity)
          } label: {
            Label(activity.title, systemImage: activity.symbol)
          }
        }
      }
    }
    Button("Take the Island Tour") { IslandTourController.shared.start() }
    Divider()
    Button(action: openUpdateDialog) {
      Label(updater.availableVersion.map { L10n.tr("Update to %@", $0) } ?? L10n.tr("Check for Updates"),
            systemImage: "arrow.down.circle")
    }
    .disabled(updater.isChecking)
    Button("Settings…") {
      NotchShelfController.shared.dismissShelf()
      SettingsWindowController.shared.show()
    }
    Button("Clear Screenshots…", role: .destructive) {
      presentation.isPresentingConfirmation = true
    }
    .disabled(store.entries.isEmpty)
  }

  private func openUpdateDialog() {
    NotchShelfController.shared.dismissShelf()
    updater.checkInteractively()
  }

  /// The shape's corner/shoulder blend: open, or part-way for the HUD card so it reads as a card.
  private func shapeExpansion(_ expanded: Bool, _ geometry: NotchGeometry) -> CGFloat {
    if expanded { return 1 }
    // HUD card bottom radius 28: (28 - 11) / (40 - 11). On the pill, corner 26: (26 - 18) / 26.
    guard route.isHUD && geometry.hudHovered else { return 0 }
    return geometry.isFloating ? 0.31 : 0.586
  }

  private var compactContent: some View {
    let geometry = layoutGeometry
    return Group {
      switch route {
      case .hud(let flash):
        hudContent(flash, geometry)
      case .notification:
        if let item = notifications.current {
          NotificationCompactView(
            content: item, overflow: notifications.overflow, notchWidth: geometry.isFloating ? 0 : geometry.notchWidth,
            wing: geometry.isFloating ? 0 : (geometry.collapsedSize.width - geometry.notchWidth) / 2,
            shoulder: geometry.closedShoulder)
            .id(item.id)
            .transition(.blurReplace)
        }
      case .idle:
        glanceWings(geometry)
      case .activity:
        activityRow(geometry)
      }
    }
    .frame(width: geometry.collapsedSize.width, height: geometry.collapsedSize.height,
           alignment: route.isHUD ? .top : .center)
  }

  /// Volume, brightness, drive and network flashes: a strip beside (or under) the camera that grows
  /// into a card on hover. The strip is click-through; the card takes clicks for its action.
  private func hudContent(_ flash: IslandFlash, _ geometry: NotchGeometry) -> some View {
    let metrics = geometry.hudMetrics
    return HUDMorphView(flash: flash, metrics: metrics, expanded: geometry.hudHovered, below: geometry.hudBelowNotch)
      .compositingGroup()
      .offset(y: geometry.hudBelowNotch && !geometry.hudHovered ? metrics.closedHeight : 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// Idle notch: the chosen glances flank the camera housing.
  private func glanceWings(_ geometry: NotchGeometry) -> some View {
    HStack(spacing: 0) {
      if geometry.glanceLeft > 0 {
        IslandGlanceView(slot: .left, model: glances)
          .padding(.leading, NotchGeometry.compactPadding)
      }
      Spacer(minLength: 0)
      if geometry.glanceRight > 0 {
        IslandGlanceView(slot: .right, model: glances)
          .padding(.trailing, NotchGeometry.compactPadding)
      }
    }
    .frame(height: geometry.collapsedSize.height)
    .opacity(geometry.isFloating ? 0 : 1)
  }

  /// On the pill the glances ride in small capsules of their own on either side.
  @ViewBuilder
  private func pillGlances(_ geometry: NotchGeometry) -> some View {
    if geometry.isFloating, route == .idle {
      HStack(spacing: 0) {
        Color.clear.frame(width: 0).overlay(alignment: .trailing) {
          pillGlance(.left, height: geometry.collapsedSize.height).padding(.trailing, NotchGeometry.bubbleGap)
        }
        Color.clear.frame(width: geometry.collapsedSize.width)
        Color.clear.frame(width: 0).overlay(alignment: .leading) {
          pillGlance(.right, height: geometry.collapsedSize.height).padding(.leading, NotchGeometry.bubbleGap)
        }
      }
      .frame(height: geometry.collapsedSize.height)
    }
  }

  @ViewBuilder
  private func pillGlance(_ slot: GlanceSlot, height: CGFloat) -> some View {
    let shown = slot == .left ? glances.visible(for: slot).reversed() : glances.visible(for: slot)
    if !shown.isEmpty {
      HStack(spacing: 10) {
        ForEach(Array(shown), id: \.self) { glance in IslandGlanceContent(glance: glance, model: glances) }
      }
      .padding(.horizontal, 12).frame(height: height)
      .background(.black, in: Capsule())
      .transition(.opacity.combined(with: .scale(scale: 0.85)))
      .fixedSize()
    }
  }

  /// A live activity in the closed island. Notch: glyph centred in the left wing, value centred in
  /// the right, both clear of the housing. Pill: music, calls and recording keep their glyph at the
  /// leading end (and waveform at the trailing one); every other activity is one centred glyph + value group (see `CompactLayout`).
  private func activityRow(_ geometry: NotchGeometry) -> some View {
    HStack(spacing: 0) {
      if let activity = activities.primary, geometry.hasLiveActivity {
        if !geometry.isFloating {
          let wings = notchWings(geometry)
          CompactWingsRow(
            leftWing: wings.left, rightWing: wings.right, notchWidth: geometry.notchWidth, shoulder: geometry.closedShoulder
          ) {
            activityLeading(activity, geometry)
          } trailing: {
            compactTrailing(activity)
          }
        } else if NotchGeometry.pillSplitsEnds(activity) {
          HStack(spacing: 0) {
            activityLeading(activity, geometry)
            Spacer(minLength: CompactLayout.groupSpacing)
            compactTrailing(activity)
          }
          .padding(.horizontal, CompactLayout.pillLeading)
        } else {
          CompactGroupRow {
            activityLeading(activity, geometry)
          } trailing: {
            compactTrailing(activity)
          }
        }
      }
    }
    .frame(height: geometry.collapsedSize.height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(activities.primary?.title ?? "Brim")
  }

  /// The two wings of the closed notch: uneven when the left one carries a track title.
  private func notchWings(_ geometry: NotchGeometry) -> (left: CGFloat, right: CGFloat) {
    let base = (geometry.collapsedSize.width - geometry.notchWidth) / 2
    let skew = (geometry.wingExtras.left - geometry.wingExtras.right) / 2
    return (max(0, base + skew), max(0, base - skew))
  }

  @ViewBuilder
  private func activityLeading(_ activity: IslandActivity, _ geometry: NotchGeometry) -> some View {
    HStack(spacing: 6) {
      activityGlyph(activity).frame(width: NotchGeometry.compactGlyph, height: NotchGeometry.compactGlyph)
      if activity == .music, compactTitle != nil, let track = nowPlaying.track {
        CompactTrackTitle(track: track, hasNotch: !geometry.isFloating, width: geometry.compactTitleWidth)
      }
    }
  }

  @ViewBuilder
  private func compactTrailing(_ activity: IslandActivity) -> some View {
    if CompactActivityHooks.drawsTrailing(activity) {
      CompactActivityHooks.trailing(activity, center: extensions)
    } else {
      defaultCompactTrailing(activity)
    }
  }

  @ViewBuilder
  private func defaultCompactTrailing(_ activity: IslandActivity) -> some View {
    switch activity {
    case .recording:
      EmptyView()
    case .timer:
      if let timer = timers.activeTimer {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          CompactTimerReadout(remaining: timer.remaining(at: context.date))
        }
      }
    case .call:
      Image(systemName: "waveform").font(.system(size: 14))
        .foregroundStyle(.green.opacity(0.85)).frame(width: 23)
    case .music:
      if let track = nowPlaying.track {
        AutomixWaveformSlot(track: track).frame(width: 23, height: 18)
      } else {
        PlaybackWaveform(isPlaying: false).frame(width: 23, height: 18)
      }
    case .agent where extensions.coding.session?.isLive() == true:
      if let session = extensions.coding.session {
        AgentStateIndicator(session: session, liveCount: extensions.coding.sessions.filter { $0.isLive() }.count)
      }
    case .system:
      if let flash = extensions.flashes.current {
        IslandFlashReadout(flash: flash, floating: presentation.geometry.isFloating)
          .transition(.blurReplace)
          .id(flash.id)
      }
    default:
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        Text(extensions.compactValue(activity)).font(CompactLayout.labelFont)
          .foregroundStyle(IslandInk.primary)
          .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).truncationMode(.tail)
          .frame(maxWidth: NotchGeometry.compactTrailingWidth(for: activity))
          .contentTransition(.numericText())
      }
    }
  }

  @ViewBuilder
  private func activityGlyph(_ activity: IslandActivity) -> some View {
    if CompactActivityHooks.drawsGlyph(activity) {
      CompactActivityHooks.glyph(activity, center: extensions)
    } else {
      defaultActivityGlyph(activity)
    }
  }

  @ViewBuilder
  private func defaultActivityGlyph(_ activity: IslandActivity) -> some View {
    switch activity {
    case .recording:
      RecordingStatusDot().matchedGeometryEffect(id: "recording-dot", in: activityNamespace)
    case .timer:
      if let timer = timers.activeTimer {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          TimerProgressGlyph(
            remaining: timer.remaining(at: context.date), duration: timer.duration,
            paused: timer.isPaused)
        }
      }
    case .call:
      CallCompactGlyph()
    case .music:
      CompactArtwork(image: nowPlaying.track?.artwork, size: 24)
        .modifier(ElasticStretch(stretch: presentation.trackStretch, reduceMotion: reduceMotion, reference: 30))
    case .browser:
      if let browser = extensions.browser.snapshot?.browser ?? extensions.browser.frontBrowser {
        BrowserIcon(browser: browser).frame(width: 18, height: 18)
      }
    case .agent where extensions.coding.session?.isLive() == true:
      AgentGlyph(tool: extensions.coding.session?.tool ?? .claude, size: 20)
        // A one-shot hop on state changes; a repeating animation re-rendered the notch every frame.
        .keyframeAnimator(initialValue: 0.0, trigger: extensions.coding.session?.state) { glyph, lift in
          glyph.offset(y: lift)
        } keyframes: { _ in
          SpringKeyframe(-3, duration: 0.18)
          SpringKeyframe(0, duration: 0.3)
        }
    case .recorder:
      Image(systemName: "waveform").font(.system(size: CompactLayout.glyphSize, weight: .semibold))
        .foregroundStyle(IslandTint.recording).symbolEffect(.variableColor.iterative, isActive: true)
    case .devices where extensions.batteries.announced != nil:
      Image(systemName: extensions.batteries.announced?.glyph ?? activity.symbol)
        .font(.system(size: CompactLayout.glyphSize, weight: .semibold)).foregroundStyle(.white)
        .contentTransition(.symbolEffect(.replace))
    case .system:
      if let flash = extensions.flashes.current {
        Image(systemName: flash.symbol).font(.system(size: CompactLayout.glyphSize, weight: .semibold))
          .foregroundStyle(flash.tint)
          .contentTransition(.symbolEffect(.replace))
          .symbolEffect(.bounce, value: flash.id)
      }
    default:
      Image(systemName: activity.symbol).font(.system(size: CompactLayout.glyphSize, weight: .semibold))
        .foregroundStyle(IslandTint.color(for: activity))
    }
  }

  /// One detached bubble: a black circle as tall as the island, `bubbleGap` off its `side`. A click
  /// opens that activity (on the closed island the controller's hit test does it).
  @ViewBuilder
  private func bubble(_ side: IslandBubbleSide, geometry: NotchGeometry) -> some View {
    if let activity = presentation.bubbles.activity(on: side), !route.isHUD, route != .notification {
      let size = geometry.secondarySize
      let travel = size.width + NotchGeometry.bubbleGap
      Button {
        selectActivity(activity)
      } label: {
        minimalGlyph(activity, diameter: size.height)
          .frame(width: size.width, height: size.height)
          .background(.black, in: Circle())
          .overlay {
            // External displays draw the island with a hairline edge; the bubble matches it.
            if geometry.isSimulatedNotch { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.75) }
          }
          .contentShape(Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.9))
      .accessibilityLabel("Show \(activity.title)")
      .help(activity.title)
      .offset(x: side == .trailing ? travel : -travel)
      .transition(.islandBubble(side, travel: travel, reduceMotion: reduceMotion))
    }
  }

  /// What a bubble shows: see `IslandBubbleContent`.
  private func minimalGlyph(_ activity: IslandActivity, diameter: CGFloat) -> some View {
    IslandBubbleContent(activity: activity, diameter: diameter, nowPlaying: nowPlaying, timers: timers,
                        extensions: extensions) {
      activityGlyph(activity)
    }
  }

}
