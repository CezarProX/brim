import AppKit
import SwiftUI

/// What sits inside the open island on each island page: the app's real views, fed fixtures.
struct OnboardingIslandContent: View {
  let page: OnboardingPage
  @ObservedObject var fixtures: OnboardingFixtures
  @ObservedObject var replies: TourReplyModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    switch page {
    case .welcome: welcome
    case .tray: tray
    case .transform: transform
    case .clipboard: clipboard
    case .player, .glass: player
    case .live: live
    case .replies: TourReplyIsland(model: replies)
    case .widgets: widgets
    case .almostThere: pill
    default: EmptyView()
    }
  }

  // MARK: Welcome

  private var welcome: some View {
    VStack(spacing: 14) {
      HStack(spacing: 16) {
        Image(nsImage: AppIconRenderer.image(for: .standard, size: 128)).resizable().frame(width: 72, height: 72)
          .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        VStack(alignment: .leading, spacing: 3) {
          Text("Brim").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
          Text("Your notch, supercharged.").font(.system(size: 14, weight: .medium)).foregroundStyle(IslandInk.secondary)
        }
      }
      HStack(spacing: 10) {
        ForEach(["camera.viewfinder", "tray.full.fill", "music.note", "doc.on.clipboard", "bolt.fill"], id: \.self) { symbol in
          Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            .frame(width: 34, height: 28).background(IslandFill.raised, in: Capsule())
        }
      }
    }
    .padding(.top, 40)
  }

  // MARK: Tray

  private var tray: some View {
    FileTrayView(store: fixtures.tray, selection: [])
      .padding(.top, 36)
  }

  // MARK: Transform

  private var transform: some View {
    TransformPanelView(urls: [fixtures.files.photo], close: {})
      .padding(.horizontal, 22).padding(.top, 8)
      .frame(width: TransformPanelView.preferredWidth, height: TransformPanelView.preferredHeight, alignment: .top)
      .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.74), .init(color: .clear, location: 0.93)],
                           startPoint: .top, endPoint: .bottom))
  }

  // MARK: Clipboard

  private var clipboard: some View {
    HStack(spacing: 14) {
      ForEach(Array(fixtures.clipboard.enumerated()), id: \.element.id) { offset, entry in
        ClipboardCard(item: .clipboard(entry), detail: Self.detail(entry), onCopy: {}, onTogglePin: nil, mark: offset == 0 ? .cursor : .none) {
          preview(entry).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 164)
      }
    }
    .padding(.top, 42)
    .allowsHitTesting(false)
  }

  private static func detail(_ entry: ClipboardEntry) -> String {
    switch entry.kind {
    case .color:
      let color = entry.text.flatMap(ClipboardEntry.color(from:))?.usingColorSpace(.sRGB)
      guard let color else { return "Color" }
      return "RGB \(Int(color.redComponent * 255)), \(Int(color.greenComponent * 255)), \(Int(color.blueComponent * 255))"
    default: return "\(entry.text?.count ?? 0) characters"
    }
  }

  @ViewBuilder
  private func preview(_ entry: ClipboardEntry) -> some View {
    switch entry.kind {
    case .color:
      let color = entry.text.flatMap(ClipboardEntry.color(from:)).map(Color.init(nsColor:)) ?? .gray
      RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color).padding(8)
        .overlay { Text(entry.text ?? "").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(.white) }
    case .link:
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: "link.circle.fill").font(.system(size: 22)).foregroundStyle(Color(red: 0.4, green: 0.65, blue: 1))
        Text(verbatim: "developer.apple.com").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        Text(verbatim: "/design").font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
    default:
      Text(entry.text ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineSpacing(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
    }
  }

  // MARK: Player

  @ViewBuilder
  private var player: some View {
    if let sample = fixtures.sample {
      let size = MusicPlayerCard.preferredSize(showsQueue: true, topInset: 36)
      MusicPlayerCard(model: sample, queue: fixtures.queue, topInset: 36, showsQueue: .constant(true))
        .frame(width: size.width, height: size.height).allowsHitTesting(false)
    } else {
      ProgressView().controlSize(.small).padding(.top, 90)
    }
  }

  // MARK: Downloads and meetings

  private var live: some View {
    VStack(spacing: 10) {
      TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
        let seconds = timeline.date.timeIntervalSinceReferenceDate
        let fraction = reduceMotion ? 0.64 : 0.2 + 0.72 * ((seconds / 7).truncatingRemainder(dividingBy: 1))
        DownloadActivityCard(snapshot: DownloadSnapshot(
          name: "Xcode_26.xip", bytes: Int64(fraction * 4_200_000_000), fraction: fraction, secondsLeft: (1 - fraction) * 90, count: 1))
      }
      meetingRow
    }
    .padding(.horizontal, 22).padding(.top, 40)
  }

  private var meetingRow: some View {
    HStack(spacing: IslandSpace.l) {
      Image(systemName: "video.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 52, height: 52).background(Color.green.gradient, in: Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text("Design review").font(IslandFont.title).foregroundStyle(IslandInk.primary)
        Text(verbatim: "Starts in 4 min · Work").font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
      }
      Spacer(minLength: 0)
      Button {} label: { Text("Join") }.buttonStyle(IslandPillStyle(prominent: true, tint: .green))
    }
    .padding(IslandSpace.l)
    .glassCard(radius: IslandRadius.medium)
  }

  // MARK: Widgets

  private var widgets: some View {
    let tiles: [IslandWidgetTile] = [.nowPlaying, .clipboard, .calendar, .timer, .weather, .stats, .notes, .screenshot]
    return LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(IslandWidgetGrid.columnWidth), spacing: 0), count: IslandWidgetGrid.columns),
      spacing: IslandWidgetGrid.rowSpacing
    ) {
      ForEach(tiles) { tile in
        VStack(spacing: IslandWidgetGrid.labelGap) {
          IslandWidgetIcon(tile: tile)
            .overlay(alignment: .topTrailing) {
              if tile == .nowPlaying {
                Circle().fill(Color.green).frame(width: 9, height: 9).overlay { Circle().stroke(.black, lineWidth: 1.5) }.offset(x: 2, y: -2)
              }
            }
          Text(tile.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary.opacity(0.92))
            .lineLimit(2).multilineTextAlignment(.center).frame(width: IslandWidgetGrid.columnWidth - 6)
        }
        .frame(width: IslandWidgetGrid.columnWidth, height: IslandWidgetGrid.tileHeight, alignment: .top)
      }
    }
    .padding(.top, 36 + IslandWidgetGrid.topPadding)
    .frame(maxWidth: .infinity, alignment: .top)
    .allowsHitTesting(false)
  }

  // MARK: Closed pill

  private var pill: some View {
    HStack {
      if let cover = fixtures.cover {
        Image(nsImage: cover).resizable().scaledToFill().frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
      Spacer()
      TourBars()
    }
    .padding(.horizontal, 26).padding(.top, 7)
  }
}

/// Five bars bouncing like a live waveform.
struct TourBars: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 2.5) {
        ForEach(0..<5, id: \.self) { index in
          let level = reduceMotion ? 0.6 : 0.35 + 0.65 * abs(sin(time * 3.1 + Double(index) * 1.3))
          Capsule().fill(Color(red: 0.4, green: 0.65, blue: 1)).frame(width: 2.5, height: 4 + 12 * level)
        }
      }
      .frame(height: 18)
    }
  }
}
