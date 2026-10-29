import SwiftUI

/// Sizes for the HUD surface. The shell sizes the island shape to these, then draws
/// `HUDMorphView` inside it.
struct HUDMetrics: Equatable {
  /// Width of the camera housing / closed notch.
  var notchWidth: CGFloat
  /// Height of the closed notch.
  var closedHeight: CGFloat
  /// The floating pill: no camera, so the strip is one centred group and the card has no
  /// empty band at the top.
  var floating = false
  /// The narrowest notch wing; wider readouts grow it (see `stripWing(for:)`).
  static let wing: CGFloat = 70
  static let cardWing: CGFloat = 120
  static let cardBodyHeight: CGFloat = 54
  /// A hero card (Full Battery) leads with a large glowing glyph.
  static let heroBodyHeight: CGFloat = 78
  static let actionRowHeight: CGFloat = 30
  /// The pill's card: a compact rounded HUD, like the system's own volume HUD.
  static let pillCardWidth: CGFloat = 300
  /// The AirPods card needs the model, "Connected" over the name and three level rings side by side.
  static let pillAirPodsCardWidth: CGFloat = 400
  static let pillCardInset = EdgeInsets(top: 15, leading: 20, bottom: 16, trailing: 20)
  static let pillCardSpacing: CGFloat = 10

  /// The narrowest notch strip (both wings at their minimum).
  var stripSize: CGSize { CGSize(width: notchWidth + 2 * Self.wing, height: closedHeight) }

  /// One notch wing for this flash: wide enough for its readout, never under the housing.
  func stripWing(for flash: IslandFlash) -> CGFloat {
    max(Self.wing, CompactLayout.wing(content: CompactLayout.readoutWidth(flash, floating: false)))
  }

  /// A centred glyph + readout group (the pill, or the strip hung below the camera).
  func groupWidth(for flash: IslandFlash) -> CGFloat {
    max(NotchGeometry.islandClosedWidth,
        CompactLayout.pillWidth(content: CompactLayout.readoutWidth(flash, floating: true)))
  }

  func stripSize(for flash: IslandFlash) -> CGSize {
    floating
      ? CGSize(width: groupWidth(for: flash), height: closedHeight)
      : CGSize(width: notchWidth + 2 * stripWing(for: flash), height: closedHeight)
  }

  /// The strip hung under the camera: as wide as the housing, or the group if that is wider.
  func belowStripWidth(for flash: IslandFlash) -> CGFloat { max(notchWidth, groupWidth(for: flash)) }

  func cardSize(for flash: IslandFlash) -> CGSize {
    if floating {
      let base = flash.airPods == nil ? Self.pillCardWidth : Self.pillAirPodsCardWidth
      return CGSize(width: max(base, stripSize(for: flash).width), height: Self.pillCardHeight(for: flash))
    }
    let extra = (flash.action == nil && flash.airPods == nil) ? 0 : Self.actionRowHeight
    return CGSize(width: max(notchWidth + 2 * Self.cardWing, stripSize(for: flash).width),
                  height: closedHeight + (flash.hero ? Self.heroBodyHeight : Self.cardBodyHeight) + extra)
  }

  /// Header (taller with a detail line, or the AirPods row), the level bar, the action row.
  static func pillCardHeight(for flash: IslandFlash) -> CGFloat {
    let header = headerHeight(for: flash)
    let bar: CGFloat = flash.airPods == nil && flash.value != nil ? pillCardSpacing + 7 : 0
    let actions: CGFloat = flash.action != nil ? pillCardSpacing + 26 : 0
    return pillCardInset.top + header + bar + actions + pillCardInset.bottom
  }

  static func headerHeight(for flash: IslandFlash) -> CGFloat {
    if flash.airPods != nil { return cardBodyHeight }
    if flash.hero { return 52 }
    return flash.detail != nil || flash.elapsedSince != nil ? 34 : 24
  }

  func size(for flash: IslandFlash, expanded: Bool) -> CGSize {
    expanded ? cardSize(for: flash) : stripSize(for: flash)
  }
}

/// The closed HUD. On a notch: the symbol centred in the left wing, the level bar and percent
/// (or the title) centred in the right one, nothing under the camera housing. On the pill, or
/// hung below the camera: symbol and readout as one centred group.
struct HUDStripView: View {
  let flash: IslandFlash
  let metrics: HUDMetrics
  /// Drawn in the band under the camera rather than beside it.
  var below = false

  var body: some View {
    if metrics.floating || below {
      CompactGroupRow {
        symbol
      } trailing: {
        IslandFlashReadout(flash: flash, floating: true)
      }
      .frame(width: below ? metrics.belowStripWidth(for: flash) : metrics.stripSize(for: flash).width,
             height: metrics.closedHeight)
    } else {
      let wing = metrics.stripWing(for: flash)
      CompactWingsRow(leftWing: wing, rightWing: wing, notchWidth: metrics.notchWidth) {
        symbol
      } trailing: {
        IslandFlashReadout(flash: flash)
      }
      .frame(height: metrics.closedHeight)
    }
  }

  private var symbol: some View {
    HUDSymbolView(symbol: flash.symbol, tint: flash.tint, size: CompactLayout.glyphSize, id: flash.id)
      .frame(minWidth: CompactLayout.glyphSlot).frame(height: CompactLayout.glyphSlot)
  }
}

struct HUDSymbolView: View {
  let symbol: String
  let tint: Color
  let size: CGFloat
  let id: UUID

  var body: some View {
    Image(systemName: symbol).font(.system(size: size, weight: .semibold))
      .foregroundStyle(tint)
      .contentTransition(.symbolEffect(.replace))
      .frame(minWidth: size * 1.5)
  }
}

/// The larger card a strip becomes on hover: title and detail at the top of the body, a wide
/// level bar or an action below. On a notch it sits beneath the camera housing, never behind it;
/// on the pill it starts at the top, with no empty band.
struct HUDCardView: View {
  let flash: IslandFlash
  let metrics: HUDMetrics
  /// False while the card is hidden behind the strip; live content (the AirPods model) pauses.
  var active = true

  var body: some View {
    let size = metrics.cardSize(for: flash)
    Group {
      if metrics.floating {
        pillCard(size)
      } else {
        notchCard(size)
      }
    }
    .frame(width: size.width, height: size.height)
  }

  private func notchCard(_ size: CGSize) -> some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: metrics.closedHeight)
      VStack(spacing: 8) {
        if let airPods = flash.airPods {
          AirPodsCardView(batteries: airPods, detail: flash.detail ?? "Connected", active: active)
        } else {
          header
          if let value = flash.value {
            HUDLevelBar(value: value, tint: flash.tint, width: size.width - 56, height: 7)
          }
        }
        actions
      }
      .padding(.horizontal, 28).padding(.bottom, 12)
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private func pillCard(_ size: CGSize) -> some View {
    let inset = HUDMetrics.pillCardInset
    return VStack(spacing: HUDMetrics.pillCardSpacing) {
      Group {
        if let airPods = flash.airPods {
          AirPodsCardView(batteries: airPods, detail: flash.detail ?? "Connected", active: active)
        } else {
          header
        }
      }
      .frame(height: HUDMetrics.headerHeight(for: flash))
      if flash.airPods == nil, let value = flash.value {
        HUDLevelBar(value: value, tint: flash.tint, width: size.width - inset.leading - inset.trailing, height: 7)
      }
      if flash.action != nil { actions.frame(height: 26) }
    }
    .padding(inset)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var header: some View {
    if flash.hero { return AnyView(heroHeader) }
    return AnyView(standardHeader)
  }

  /// Large glowing glyph, then the title and the line beneath it (Full Battery).
  private var heroHeader: some View {
    HStack(spacing: 14) {
      Image(systemName: flash.symbol).font(.system(size: 38, weight: .regular))
        .foregroundStyle(flash.tint)
        .shadow(color: flash.tint.opacity(0.85), radius: 9)
        .shadow(color: flash.tint.opacity(0.5), radius: 20)
        .frame(width: 56)
      VStack(alignment: .leading, spacing: 2) {
        Text(flash.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        if let line = detailLine {
          line.font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var standardHeader: some View {
    HStack(spacing: 10) {
      HUDSymbolView(symbol: flash.symbol, tint: flash.tint, size: 18, id: flash.id)
      VStack(alignment: .leading, spacing: 1) {
        Text(flash.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
          .truncationMode(.tail)
        if let line = detailLine { line.font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1) }
      }
      Spacer(minLength: 8)
      if let value = flash.value {
        Text("\(HUDLevelMath.percent(value))")
          .font(IslandFont.headline).monospacedDigit().foregroundStyle(IslandInk.primary)
          .contentTransition(.numericText())
      }
    }
  }

  private var actions: some View {
    HStack(spacing: 8) {
      ForEach([flash.action, flash.secondaryAction].compactMap { $0 }) { action in
        Button { action.perform() } label: {
          Label(action.title, systemImage: action.symbol)
        }
        .buttonStyle(IslandPillStyle(prominent: action.id == flash.action?.id, tint: flash.tint, compact: true))
      }
    }
  }

  private var detailLine: Text? {
    if let since = flash.elapsedSince {
      let base = flash.detail.map { "\($0) · " } ?? ""
      return Text("\(base)") + Text(since, style: .timer)
    }
    return flash.detail.map { Text($0) }
  }
}

/// Strip that morphs into a card on the same spring when `expanded` flips (hover). The strip
/// is click-through; the card takes clicks so its action button works.
struct HUDMorphView: View {
  let flash: IslandFlash
  let metrics: HUDMetrics
  let expanded: Bool
  /// The closed strip hangs under the camera (the shell offsets it down by the notch height).
  var below = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let size = below && !expanded
      ? CGSize(width: metrics.belowStripWidth(for: flash), height: metrics.closedHeight)
      : metrics.size(for: flash, expanded: expanded)
    ZStack(alignment: .top) {
      HUDStripView(flash: flash, metrics: metrics, below: below)
        .opacity(expanded ? 0 : 1).blur(radius: expanded ? 6 : 0)
        .allowsHitTesting(false)
      HUDCardView(flash: flash, metrics: metrics, active: expanded)
        .opacity(expanded ? 1 : 0).blur(radius: expanded ? 0 : 6)
        .allowsHitTesting(expanded)
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .clipped()
    .animation(NotchMotion.expansion(expanded, reduceMotion: reduceMotion), value: expanded)
  }
}
