import AppKit
import SwiftUI

/// The look of macOS Control Center, in one place: neutral modules, white glyphs on grey discs,
/// and the system accent only on a switch that is on.
enum ControlCenterStyle {
  static let radius: CGFloat = 20
  static let module = Color.white.opacity(0.1)
  static let moduleHover = Color.white.opacity(0.15)
  static let disc = Color.white.opacity(0.16)
  static let discHover = Color.white.opacity(0.22)
  static let on = Color.accentColor
}

/// A Control Center module: a flat translucent rounded square that brightens under the pointer.
struct CommandTileSurface<Content: View>: View {
  var padding: CGFloat = 12
  @ViewBuilder var content: Content
  @State private var hovered = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: ControlCenterStyle.radius, style: .continuous)
    content
      .padding(padding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(shape.fill(hovered ? ControlCenterStyle.moduleHover : ControlCenterStyle.module))
      .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
      .contentShape(shape)
      .onHover { hovered = $0 }
      .animation(.easeOut(duration: 0.15), value: hovered)
  }
}

/// Control Center's round control: a grey disc with a white glyph, filled with the accent (glyph
/// still white) while a switch is on. `bounce` replays the symbol's bounce whenever it changes.
struct TileGlyph: View {
  let symbol: String
  var isOn = false
  var size: CGFloat = 32
  var bounce = 0

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.44, weight: .medium))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(.white)
      .contentTransition(.symbolEffect(.replace))
      .symbolEffect(.bounce, value: bounce)
      .frame(width: size, height: size)
      .background {
        ZStack {
          Circle().fill(ControlCenterStyle.disc)
          Circle().fill(ControlCenterStyle.on).opacity(isOn ? 1 : 0)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isOn)
  }
}

/// A status line that slides to its new value (Off → On) instead of snapping.
struct TileCaption: View {
  let text: String

  var body: some View {
    ZStack(alignment: .leading) {
      Text(text).font(.system(size: 11)).foregroundStyle(IslandInk.secondary).lineLimit(1).minimumScaleFactor(0.8)
        .id(text)
        .transition(.push(from: .bottom).combined(with: .opacity))
    }
    .clipped()
    .animation(.spring(duration: 0.3, bounce: 0.15), value: text)
  }
}

/// A control. Small is Control Center's square: the disc centred with its name under it.
/// Wide is its two-wide module: the disc, then the name and the state.
struct ActionTileView: View {
  let kind: TileKind
  let size: TileSize
  let facts: TileFacts
  @State private var bounce = 0

  var body: some View {
    CommandTileSurface(padding: size == .small ? 8 : 12) {
      if size == .small {
        VStack(spacing: 7) {
          TileGlyph(symbol: kind.symbol, isOn: facts.isOn, size: 36, bounce: bounce)
          Text(kind.shortTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(IslandInk.primary)
            .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(spacing: 10) {
          TileGlyph(symbol: kind.symbol, isOn: facts.isOn, size: 34, bounce: bounce)
          VStack(alignment: .leading, spacing: 1) {
            Text(kind.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary)
              .lineLimit(1).minimumScaleFactor(0.8)
            if !facts.subtitle.isEmpty { TileCaption(text: facts.subtitle) }
          }
          Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
      }
    }
    .onChange(of: facts.isOn) { _, _ in bounce += 1 }
    .help(facts.subtitle.isEmpty ? kind.title : "\(kind.title) · \(facts.subtitle)")
  }
}

/// CPU / memory / disk / battery: a thin ring around the reading, like the Batteries widget.
/// White, except battery, which is green (red when low).
struct StatTileView: View {
  let kind: TileKind
  let size: TileSize
  let facts: TileFacts
  @State private var drawn = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    CommandTileSurface(padding: size == .small ? 8 : 12) {
      if size == .small {
        VStack(spacing: 6) {
          ring(diameter: 40)
          Text(kind.title).font(.system(size: 11, weight: .medium)).foregroundStyle(IslandInk.primary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(spacing: 10) {
          ring(diameter: kind == .network ? 34 : 40)
          VStack(alignment: .leading, spacing: 1) {
            Text(kind.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary)
              .lineLimit(1).fixedSize()
            TileCaption(text: facts.subtitle)
            // Network has no ring, so its second rate goes under the first.
            if kind == .network, let value = facts.value { TileCaption(text: value) }
          }
          Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
      }
    }
    .help("\(kind.title) · \(facts.subtitle)")
    .onAppear {
      guard !reduceMotion else { drawn = true; return }
      withAnimation(.spring(duration: 0.8, bounce: 0.1).delay(0.1)) { drawn = true }
    }
  }

  private var ringColor: Color {
    guard kind == .battery else { return .white }
    return (facts.level ?? 1) <= 0.2 ? .red : .green
  }

  @ViewBuilder
  private func ring(diameter: CGFloat) -> some View {
    if let level = facts.level {
      ZStack {
        Circle().stroke(Color.white.opacity(0.16), lineWidth: 3.5)
        Circle().trim(from: 0, to: drawn ? max(0.02, min(1, level)) : 0)
          .stroke(ringColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(facts.value ?? "").font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
          .monospacedDigit().minimumScaleFactor(0.6).foregroundStyle(IslandInk.primary)
          .contentTransition(.numericText())
      }
      .frame(width: diameter, height: diameter)
      .animation(.spring(duration: 0.5, bounce: 0), value: level)
    } else {
      TileGlyph(symbol: kind.symbol, size: diameter)
    }
  }
}

/// The next calendar event, beside a Calendar-style date (red weekday over the day).
struct UpcomingTileView: View {
  let size: TileSize
  let event: CalendarAgendaItem?

  var body: some View {
    CommandTileSurface {
      HStack(spacing: 12) {
        dateBadge(event?.start ?? .now)
        VStack(alignment: .leading, spacing: 2) {
          if let event {
            Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary)
              .lineLimit(size == .hero ? 3 : 2).fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 30)) { context in
              Text(CalendarUpNext.countdown(to: event, now: context.date) + " · "
                + event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(IslandInk.secondary).lineLimit(1)
            }
          } else {
            Text("No upcoming events").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary)
            Text("Connect Calendar in Settings").font(.system(size: 11)).foregroundStyle(IslandInk.secondary)
          }
        }
        Spacer(minLength: 0)
      }
      .frame(maxHeight: .infinity)
    }
  }

  private func dateBadge(_ date: Date) -> some View {
    VStack(spacing: -1) {
      Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
        .font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
      Text(date.formatted(.dateTime.day())).font(.system(size: 22, weight: .regular)).monospacedDigit()
        .foregroundStyle(IslandInk.primary)
    }
    .frame(width: 34)
  }
}
