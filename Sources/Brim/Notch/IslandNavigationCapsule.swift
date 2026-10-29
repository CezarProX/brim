import SwiftUI

/// Top-level destinations of the expanded island: Home (the widget shelf), the Clipboard, the file
/// Tray (its tab shows only while it holds files), Music (the full player), Widgets and Messages (recent
/// chats; its tab shows only while there are some). Calendar and every tool open from the Widgets page.
enum IslandPage: Hashable, CaseIterable {
  case home, clipboard, tray, music, widgets, messages

  var title: String {
    switch self {
    case .home: "Home"
    case .clipboard: "Clipboard"
    case .tray: "File Tray"
    case .music: "Music"
    case .widgets: "Widgets"
    case .messages: "Messages"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .clipboard: "doc.on.clipboard.fill"
    case .tray: "tray.fill"
    case .music: "music.note"
    case .widgets: "square.grid.2x2.fill"
    case .messages: "bubble.left.and.bubble.right.fill"
    }
  }
}

/// The small navigation capsule centred beneath the open island: house, clipboard, tray with
/// its file count (only while it holds files), and the widget grid. Options live on right-click.
struct IslandNavigationCapsule<MenuContent: View>: View {
  let page: IslandPage
  var trayCount = 0
  /// Unread chats, shown on the Messages tab.
  var unreadCount = 0
  /// The tabs to show, in order; see `IslandPageOrder.visible`.
  var pages: [IslandPage] = IslandPage.allCases
  /// Widgets pinned beside the page buttons (up to four).
  var favorites: [IslandWidgetTile] = []
  /// Replaces the selection fill's white when the user picked a highlight colour.
  var highlight: Color?
  var openFavorite: (IslandWidgetTile) -> Void = { _ in }
  let select: (IslandPage) -> Void
  @ViewBuilder let menu: () -> MenuContent
  @Namespace private var selection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(pages, id: \.self) { destination in
        tab(destination).transition(.scale(scale: 0.6).combined(with: .opacity))
      }
      if !favorites.isEmpty {
        Capsule().fill(Color.white.opacity(0.16)).frame(width: 1, height: 16).padding(.horizontal, 3)
        ForEach(favorites) { tile in favorite(tile) }
      }
    }
    .padding(IslandNavigationLayout.inset)
    // Liquid Glass on macOS 26: SwiftUI's own glass, which fades with the capsule. Solid before:
    // an AppKit blur ignored SwiftUI's fade and showed as a blank grey pill before the island
    // opened and after it closed.
    .background { DynamicGlassCapsuleSurface(shape: Capsule(), glass: GlassSupport.hasLiquidGlass) }
    .frame(height: IslandNavigationLayout.height)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: page)
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: trayCount)
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: unreadCount)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: favorites)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: pages)
    .contextMenu { menu() }
  }

  private func tab(_ destination: IslandPage) -> some View {
    let selected = page == destination
    let count = destination == .tray ? trayCount : destination == .messages ? unreadCount : 0
    return Button { select(destination) } label: {
      HStack(spacing: 5) {
        Image(systemName: destination.symbol)
          .font(.system(size: 12, weight: .semibold))
        if count > 0 {
          Text("\(min(count, 99))")
            .font(.system(size: 10, weight: .bold)).monospacedDigit()
            .foregroundStyle(IslandInk.primary)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color.white.opacity(selected ? 0.2 : 0.14), in: Circle())
            .contentTransition(.numericText())
            .transition(.scale.combined(with: .opacity))
        }
      }
      .foregroundStyle(selected ? IslandInk.primary : IslandInk.secondary)
      .padding(.horizontal, count > 0 ? 9 : 0)
      .frame(minWidth: IslandNavigationLayout.item, minHeight: IslandNavigationLayout.item)
      .background {
        if selected {
          Capsule().fill(highlight.map { $0.opacity(0.42) } ?? Color.white.opacity(0.16))
            .matchedGeometryEffect(id: "island-page", in: selection)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .help(destination.title)
    .accessibilityLabel(count > 0 ? "\(destination.title), \(count) \(destination == .messages ? "unread" : "files")" : destination.title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func favorite(_ tile: IslandWidgetTile) -> some View {
    Button { openFavorite(tile) } label: {
      Image(systemName: tile.symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(IslandInk.secondary)
        .frame(width: IslandNavigationLayout.item, height: IslandNavigationLayout.item)
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .help(tile.title)
    .accessibilityLabel(tile.title)
    .transition(.scale.combined(with: .opacity))
  }
}
