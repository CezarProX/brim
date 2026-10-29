import SwiftUI

/// Page position, shared so the window controller (arrow keys, scroll) and the view stay in step.
@MainActor
final class CommandCenterPageState: ObservableObject {
  @Published var page = 0
  func step(_ delta: Int, count: Int) {
    page = min(max(0, page + delta), max(0, count - 1))
    AppSettings.shared.commandCenterLastPage = page
  }
}

/// The menu-bar popover: pages of tiles, page dots, and an edit mode.
struct CommandCenterView: View {
  @ObservedObject var store: CommandCenterStore
  @ObservedObject var pager: CommandCenterPageState
  var models: CommandCenterModels = CommandCenterModels()
  var onAction: (TileKind) -> Void = { _ in }
  var onClose: () -> Void = {}
  var onOpenIsland: () -> Void = {}
  /// Off for renders, which capture a single frame.
  var animatesEntrance = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var opened = false

  static let cell: CGFloat = 84
  static let gap: CGFloat = 10
  static let gridWidth = cell * CGFloat(CommandCenterLayout.columns) + gap * CGFloat(CommandCenterLayout.columns - 1)
  static let gridHeight = cell * CGFloat(CommandCenterLayout.rows) + gap * CGFloat(CommandCenterLayout.rows - 1)
  static let padding: CGFloat = 14
  static let bleed: CGFloat = 8
  static var size: CGSize { CGSize(width: gridWidth + padding * 2, height: gridHeight + 96) }

  var body: some View {
    VStack(spacing: 10) {
      header
      pagerBody
      footer
    }
    .padding(Self.padding)
    .frame(width: Self.size.width, height: Self.size.height)
    .background(CommandCenterBackdrop())
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))
    .preferredColorScheme(.dark)
    .environment(\.commandCenterEntrance, animatesEntrance && !reduceMotion)
    .scaleEffect(opened ? 1 : 0.94, anchor: .top)
    .opacity(opened ? 1 : 0)
    .onAppear {
      models.stats.attach(); models.switches.refresh()
      guard animatesEntrance, !reduceMotion else { opened = true; return }
      withAnimation(.spring(duration: 0.38, bounce: 0.22)) { opened = true }
    }
    .onDisappear { models.stats.detach() }
  }

  // MARK: Header / footer

  private var header: some View {
    HStack {
      Text(store.isEditing ? "Edit Command Center" : "Command Center")
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(IslandInk.primary)
        .contentTransition(.opacity)
      Spacer()
      if store.isEditing {
        Button("Done") { withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { store.isEditing = false } }
          .buttonStyle(IslandPillStyle(prominent: true, tint: .blue, compact: true))
      } else {
        CommandHeaderButton(symbol: "rectangle.topthird.inset.filled", label: L10n.tr("Open Island"), hoverEffect: .wiggle) { onOpenIsland() }
        CommandHeaderButton(symbol: "pencil", label: "Edit Command Center", hoverEffect: .wiggle) {
          withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { store.isEditing = true }
        }
        CommandHeaderButton(symbol: "gearshape.fill", label: "Settings", hoverEffect: .spin) { onAction(.settings) }
      }
    }
    .frame(height: 26)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: store.isEditing)
  }

  @ViewBuilder
  private var footer: some View {
    if store.isEditing {
      EditBar(store: store)
    } else {
      PageDots(count: store.pageCount, current: pager.page) { page in
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { pager.page = page }
      }
      .frame(height: 24)
    }
  }

  // MARK: Pager

  private var pagerBody: some View {
    let pages = store.pages
    let current = min(pager.page, max(0, pages.count - 1))
    return ZStack(alignment: .topLeading) {
      HStack(spacing: Self.padding * 2 + Self.bleed * 2) {
        ForEach(pages.indices, id: \.self) { index in
          pageView(pages[index])
            .opacity(index == current ? 1 : 0.3)
            .scaleEffect(index == current || reduceMotion ? 1 : 0.94)
        }
        if pages.isEmpty { emptyState }
      }
      .offset(x: -CGFloat(current) * (Self.gridWidth + Self.padding * 2 + Self.bleed * 2))
      .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: current)
      .padding(Self.bleed)
    }
    // The clip is `bleed` wider than the grid on every side, so edit badges hanging off a tile's corner stay visible.
    .frame(width: Self.gridWidth + Self.bleed * 2, height: Self.gridHeight + Self.bleed * 2, alignment: .topLeading)
    .clipped()
    .padding(-Self.bleed)
    .background(SwipeCatcher { delta in pager.step(delta, count: pages.count) })
    .gesture(DragGesture(minimumDistance: 24).onEnded { value in
      if value.translation.width < -40 { pager.step(1, count: pages.count) }
      if value.translation.width > 40 { pager.step(-1, count: pages.count) }
    })
  }

  private var emptyState: some View {
    Text("No tiles. Choose Edit to add some.").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
      .frame(width: Self.gridWidth, height: Self.gridHeight)
  }

  private func pageView(_ tiles: [PlacedTile]) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(tiles.enumerated()), id: \.element.id) { order, placed in
        tile(placed.placement)
          .frame(width: width(placed.placement.size), height: height(placed.placement.size))
          .modifier(HomeJiggle(active: store.isEditing && !reduceMotion, seed: order * 7))
          .modifier(CommandTileEntrance(order: order))
          .offset(x: CGFloat(placed.column) * (Self.cell + Self.gap), y: CGFloat(placed.row) * (Self.cell + Self.gap))
          .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }
    .frame(width: Self.gridWidth, height: Self.gridHeight, alignment: .topLeading)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: tiles.map(\.id))
  }

  private func width(_ size: TileSize) -> CGFloat { Self.cell * CGFloat(size.columns) + Self.gap * CGFloat(size.columns - 1) }
  private func height(_ size: TileSize) -> CGFloat { Self.cell * CGFloat(size.rows) + Self.gap * CGFloat(size.rows - 1) }

  // MARK: Tiles

  @ViewBuilder
  private func tile(_ placement: TilePlacement) -> some View {
    let kind = placement.kind
    ZStack(alignment: .topLeading) {
      if store.isEditing {
        tileBody(placement).allowsHitTesting(false).opacity(0.92)
          .draggable(kind.rawValue)
          .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let moved = TileKind(rawValue: id) else { return false }
            store.move(moved, onto: kind)
            return true
          }
        EditBadges(kind: kind, store: store)
      } else {
        Button { onAction(kind) } label: { tileBody(placement) }
          .buttonStyle(IslandPressStyle(pressedScale: 0.97))
          .accessibilityLabel(kind.title)
      }
    }
  }

  @ViewBuilder
  private func tileBody(_ placement: TilePlacement) -> some View {
    let kind = placement.kind
    let facts = TileFacts.make(kind, models)
    switch kind {
    case .nowPlaying: NowPlayingTileView(size: placement.size, model: models.playing)
    case .upcoming: UpcomingTileView(size: placement.size, event: TileFacts.nextEvent(models))
    case .cpu, .memory, .disk, .battery, .network: StatTileView(kind: kind, size: placement.size, facts: facts)
    default: ActionTileView(kind: kind, size: placement.size, facts: facts)
    }
  }
}

/// Remove and resize controls drawn over a tile in edit mode.
private struct EditBadges: View {
  let kind: TileKind
  @ObservedObject var store: CommandCenterStore

  var body: some View {
    ZStack {
      Button { store.remove(kind) } label: {
        Image(systemName: "minus").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
          .frame(width: 18, height: 18).background(Circle().fill(Color(white: 0.85)))
          .shadow(color: .black.opacity(0.3), radius: 2, y: 1).contentShape(Circle())
      }
      .buttonStyle(.plain).accessibilityLabel("Remove \(kind.title)")
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).offset(x: -6, y: -6)
      if kind.allowedSizes.count > 1 {
        Button { store.cycleSize(kind) } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold))
            .foregroundStyle(.black).frame(width: 18, height: 18)
            .background(Circle().fill(Color(white: 0.85)))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Resize \(kind.title)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 6, y: -6)
      }
    }
  }
}

struct PageDots: View {
  let count: Int
  let current: Int
  var select: (Int) -> Void = { _ in }

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<max(1, count), id: \.self) { index in
        Capsule().fill(index == current ? Color.white : Color.white.opacity(0.3))
          .frame(width: index == current ? 16 : 6, height: 6)
          .contentShape(Rectangle().inset(by: -4))
          .onTapGesture { select(index) }
          .animation(.spring(duration: 0.3, bounce: 0.2), value: current)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(current + 1) of \(max(1, count))")
  }
}

/// Edit mode footer: add a tile, pick a preset, reset.
private struct EditBar: View {
  @ObservedObject var store: CommandCenterStore

  var body: some View {
    HStack(spacing: 8) {
      Menu {
        let free = CommandCenterLayout.available(excluding: store.placements)
        if free.isEmpty { Text("Every tile is added") }
        ForEach(Array(Set(free.map(\.group))).sorted(), id: \.self) { group in
          Section(group) {
            ForEach(free.filter { $0.group == group }) { kind in
              Button { store.add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
            }
          }
        }
      } label: { Label("Add tile", systemImage: "plus") }
      Menu {
        ForEach(CommandCenterLayout.presets) { preset in
          Button(preset.title) { store.apply(preset) }
        }
      } label: { Label("Layout", systemImage: "rectangle.3.group") }
      Spacer(minLength: 0)
      Text("Drag to reorder").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
    }
    .menuStyle(.borderlessButton)
    .font(IslandFont.label.weight(.semibold))
    .frame(height: 24)
  }
}

/// Dark frosted surface with a faint top highlight.
struct CommandCenterBackdrop: View {
  var body: some View {
    ZStack {
      IslandGlassMaterial()
      Color.black.opacity(0.55)
      LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
    }
  }
}

/// Turns horizontal two-finger scrolls into page steps.
private struct SwipeCatcher: NSViewRepresentable {
  let onSwipe: (Int) -> Void

  func makeNSView(context: Context) -> SwipeView { SwipeView(onSwipe: onSwipe) }
  func updateNSView(_ view: SwipeView, context: Context) { view.onSwipe = onSwipe }

  final class SwipeView: NSView {
    var onSwipe: (Int) -> Void
    private var accumulated: CGFloat = 0
    private var fired = false
    init(onSwipe: @escaping (Int) -> Void) { self.onSwipe = onSwipe; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func scrollWheel(with event: NSEvent) {
      guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { super.scrollWheel(with: event); return }
      if event.phase.contains(.began) { accumulated = 0; fired = false }
      accumulated += event.scrollingDeltaX
      if !fired, abs(accumulated) > 40 { fired = true; onSwipe(accumulated < 0 ? 1 : -1) }
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) { accumulated = 0; fired = false }
    }
  }
}

// MARK: Motion

private struct CommandCenterEntranceKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  /// Whether tiles cascade in when the Command Center opens.
  var commandCenterEntrance: Bool {
    get { self[CommandCenterEntranceKey.self] }
    set { self[CommandCenterEntranceKey.self] = newValue }
  }
}

/// Tiles rise into place one after another when the popover opens, in reading order.
private struct CommandTileEntrance: ViewModifier {
  let order: Int
  @Environment(\.commandCenterEntrance) private var animates
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .opacity(shown || !animates ? 1 : 0)
      .scaleEffect(shown || !animates ? 1 : 0.86)
      .offset(y: shown || !animates ? 0 : 10)
      .onAppear {
        guard animates, !shown else { return }
        withAnimation(.spring(duration: 0.42, bounce: 0.3).delay(0.05 + Double(order) * 0.028)) { shown = true }
      }
  }
}

/// A round header button that brightens under the pointer and plays a small hint of what it does.
private struct CommandHeaderButton: View {
  enum HoverEffect { case wiggle, spin }

  let symbol: String
  let label: String
  let hoverEffect: HoverEffect
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        .foregroundStyle(hovered ? IslandInk.primary : IslandInk.secondary)
        .rotationEffect(.degrees(rotation))
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.white.opacity(hovered ? 0.18 : 0.09)))
        .overlay(Circle().strokeBorder(Color.white.opacity(hovered ? 0.2 : 0.08), lineWidth: 0.6))
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.85))
    .onHover { hovered = $0 }
    .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.45), value: hovered)
    .help(label).accessibilityLabel(label)
  }

  private var rotation: Double {
    guard hovered, !reduceMotion else { return 0 }
    return hoverEffect == .spin ? 90 : -14
  }
}
