import SwiftUI

/// Annular sector centered on 12 o'clock, rotated by the caller to follow the pointer.
struct RingWedge: Shape {
  var innerRadius: CGFloat
  var outerRadius: CGFloat
  var width: Double

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let start = Angle.degrees(-90 - width / 2)
    let end = Angle.degrees(-90 + width / 2)
    var path = Path()
    path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
    path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
    path.closeSubpath()
    return path
  }
}

/// The radial menu: dark glass disc, a wedge that follows the pointer, and up to eight slots.
struct RingView: View {
  static let side: CGFloat = 320
  static let radius: CGFloat = 106
  @ObservedObject var model: RingViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      disc
      wedge
      center
      slotsLayer.id(model.ringIndex)
        .transition(reduceMotion ? .opacity : .asymmetric(
          insertion: .scale(scale: model.switchStep > 0 ? 0.82 : 1.18).combined(with: .opacity),
          removal: .scale(scale: model.switchStep > 0 ? 1.18 : 0.82).combined(with: .opacity)))
    }
    .frame(width: Self.side, height: Self.side)
    .contentShape(Circle())
    .onContinuousHover(coordinateSpace: .local) { phase in
      switch phase {
      case .active(let point):
        model.pointerMoved(dx: point.x - Self.side / 2, dy: point.y - Self.side / 2)
      case .ended: model.pointerLeft()
      }
    }
    .onTapGesture { model.chooseHovered() }
    .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.3), value: model.ringIndex)
    .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.22), value: model.highlightAngle)
    .animation(.spring(duration: 0.2, bounce: 0.2), value: model.hovered)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: model.appeared)
    .onAppear { model.appeared = true }
    .preferredColorScheme(.dark)
  }

  private var disc: some View {
    Circle().fill(.black.opacity(0.8))
      .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 0.75) }
      .overlay {
        Circle().stroke(.white.opacity(0.06), lineWidth: 0.75)
          .frame(width: RingGeometry.deadZone * 2, height: RingGeometry.deadZone * 2)
      }
      .frame(width: Self.side - 24, height: Self.side - 24)
      .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
      .scaleEffect(model.appeared || reduceMotion ? 1 : 0.55)
      .opacity(model.appeared ? 1 : 0)
  }

  private var wedge: some View {
    let tint = model.hoveredSlot?.color ?? .white
    return RingWedge(
      innerRadius: RingGeometry.deadZone, outerRadius: (Self.side - 24) / 2 - 2,
      width: 360.0 / Double(RingPage.slotCount) - 3
    )
    .fill(tint.opacity(model.hovered == nil ? 0 : 0.22))
    .rotationEffect(.degrees(model.highlightAngle))
    .frame(width: Self.side, height: Self.side)
  }

  private var center: some View {
    VStack(spacing: 3) {
      if let slot = model.hoveredSlot {
        Image(systemName: slot.symbol).font(.system(size: 17, weight: .semibold))
          .foregroundStyle(slot.color).contentTransition(.symbolEffect(.replace))
        Text(slot.title).font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.primary)
          .lineLimit(1).contentTransition(.opacity)
      } else {
        Text(model.ring.name).font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary)
          .lineLimit(1)
        if model.layout.rings.count > 1 { dots }
      }
    }
    .frame(width: RingGeometry.deadZone * 2 - 8)
    .opacity(model.appeared ? 1 : 0)
  }

  private var dots: some View {
    HStack(spacing: 4) {
      ForEach(model.layout.rings.indices, id: \.self) { index in
        Circle().fill(index == model.ringIndex ? Color.white : Color.white.opacity(0.28)).frame(width: 5, height: 5)
      }
    }
    .accessibilityHidden(true)
  }

  private var slotsLayer: some View {
    ZStack {
      ForEach(Array(model.slots.enumerated()), id: \.offset) { index, slot in
        if let slot { slotView(slot, index: index) }
      }
    }
  }

  private func slotView(_ slot: RingSlot, index: Int) -> some View {
    let active = model.hovered == index
    let open = model.appeared || reduceMotion
    return Image(systemName: slot.symbol)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(active ? Color.black : slot.color)
      .frame(width: 48, height: 48)
      .background(active ? slot.color : IslandFill.raised, in: Circle())
      .scaleEffect(active && !reduceMotion ? 1.16 : 1)
      .offset(RingGeometry.offset(index: index, count: RingPage.slotCount, radius: open ? Self.radius : 18))
      .opacity(open ? 1 : 0)
      .animation(
        reduceMotion ? nil : .spring(duration: 0.44, bounce: 0.38).delay(Double(index) * 0.018),
        value: model.appeared
      )
      .accessibilityElement()
      .accessibilityLabel(slot.title)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { model.onChoose(slot) }
  }
}
