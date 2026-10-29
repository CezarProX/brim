import AppKit
import SwiftUI

/// A layered glass card (`GlassCardBackground`) on the island,
/// with a sheen and a hairline rim that catches the light. Every Home widget sits in one so the shelf reads as a single family.
struct HomeWidgetCard<Content: View>: View {
  static var padding: CGFloat { 14 }
  var fill: Color? = nil
  var padding: CGFloat = Self.padding
  @ViewBuilder var content: () -> Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
    content()
      .padding(padding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background { GlassCardBackground(shape: shape, fill: fill) }
      .clipShape(shape)
  }
}

/// The one header style: a small tinted glyph, the title, and an optional trailing caption.
struct HomeWidgetHeader<Trailing: View>: View {
  let title: String
  let symbol: String
  var tint: Color = IslandInk.secondary
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
      Text(title).font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      Spacer(minLength: 4)
      trailing()
    }
    .frame(height: 16)
  }
}

extension HomeWidgetHeader where Trailing == EmptyView {
  init(title: String, symbol: String, tint: Color = IslandInk.secondary) {
    self.init(title: title, symbol: symbol, tint: tint) { EmptyView() }
  }
}

/// One shelf widget inside its card, laid out for its size. Weather and Stats draw their own cards
/// at medium, so they go in bare.
@MainActor
struct HomeWidgetContent: View {
  let widget: HomeWidget
  var size: HomeWidgetSize
  @ObservedObject var center: ActivityCenter
  @ObservedObject var store: ShelfStore
  @ObservedObject var nowPlaying: NowPlayingModel
  let openTool: (IslandActivity) -> Void
  let showShelf: () -> Void
  @ObservedObject private var stats = SystemStatsModel.shared
  @ObservedObject private var awake = KeepAwakeModel.shared

  var body: some View {
    switch (widget, size) {
    case (.media, _): HomeIdlePlayerCard(model: nowPlaying, size: size)
    case (.weather, .medium): WeatherWidgetView().frame(maxHeight: .infinity)
    case (.weather, .small): HomeWeatherSmallWidget()
    case (.stats, .medium): StatsWidgetView(stats: stats, fillsHeight: true).frame(maxHeight: .infinity)
    case (.captures, .small): HomeCapturesSmallWidget(store: store)
    case (.batteries, .small): HomeWidgetCard(padding: 12) { HomeBatteriesWidget(model: center.batteries, size: .small) }
    default: HomeWidgetCard { cardBody }
    }
  }

  @ViewBuilder private var cardBody: some View {
    switch widget {
    case .clock: HomeClockWidget(calendar: center.calendar, size: size)
    case .captures: captures
    case .timer:
      if size == .small { HomeTimerSmallWidget(model: center.focus) } else { TimerWidget(model: center.focus) }
    case .notes:
      if size == .small { HomeNotesSmallWidget(model: .shared) } else { NotesWidget(model: .shared) }
    case .agenda: HomeAgendaWidget(calendar: center.calendar, size: size, open: { openTool(.calendar) })
    case .batteries: HomeBatteriesWidget(model: center.batteries, size: size)
    case .awake: awakeWidget
    case .lyrics: HomeLyricsWidget(model: .shared, nowPlaying: nowPlaying)
    case .stats: HomeStatsSmallWidget(stats: stats)
    case .media, .weather: EmptyView()
    }
  }

  private var captures: some View {
    VStack(alignment: .leading, spacing: 8) {
      HomeWidgetHeader(title: "Captures", symbol: "camera.viewfinder") {
        if !store.entries.isEmpty {
          Button("All", action: showShelf).font(IslandFont.caption.weight(.semibold))
            .foregroundStyle(IslandInk.tertiary).buttonStyle(IslandPressStyle())
        }
      }
      if store.entries.isEmpty {
        Button { CaptureCoordinator.shared.startCapture() } label: {
          VStack(spacing: 6) {
            Image(systemName: "plus.viewfinder").font(.system(size: 22, weight: .medium))
            Text("Take a screenshot").font(IslandFont.label)
          }
          .foregroundStyle(IslandInk.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .glassCard(radius: IslandRadius.medium)
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.97))
      } else {
        CapturePile(store: store)
      }
    }
  }

  private var awakeWidget: some View {
    VStack(spacing: 8) {
      HomeWidgetHeader(title: "High Alert", symbol: "cup.and.saucer.fill")
      Spacer(minLength: 0)
      Button {
        if awake.isActive { awake.stop() } else { awake.start(minutes: nil) }
      } label: {
        Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(awake.isActive ? Color.black : IslandInk.primary)
          .frame(width: 52, height: 52)
          .background(awake.isActive ? Color.yellow : IslandFill.raised, in: Circle())
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.9))
      Text(awake.isActive ? "Awake" : "Off").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }
}
