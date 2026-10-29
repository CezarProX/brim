import SwiftUI

/// The Batteries widget, as Apple draws it: one level ring per battery (the Mac, AirPods earbuds,
/// their case, mouse, keyboard) with the device's own glyph inside and the level underneath.
/// Medium: up to four rings in a row under the header. Small: a 2×2 grid of rings, or one large
/// ring when only one battery is known.
@MainActor
struct HomeBatteriesWidget: View {
  @ObservedObject var model: DeviceBatteryModel
  var size: HomeWidgetSize = .medium

  /// Apple's widget fits four rings across.
  static let maxRings = 4
  static let ringSize: CGFloat = 40
  static let smallRingSize: CGFloat = 34

  private var rings: [BatteryRingItem] { BatteryRingItem.items(model.devices, limit: Self.maxRings) }

  var body: some View {
    let rings = rings
    Group {
      if size == .small { small(rings) } else { medium(rings) }
    }
    .animation(.spring(duration: 0.4, bounce: 0.1), value: model.devices)
    .onAppear { model.refresh() }
  }

  private func medium(_ rings: [BatteryRingItem]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HomeWidgetHeader(title: "Batteries", symbol: "battery.100percent", tint: .green)
      if rings.isEmpty {
        emptyState
      } else {
        HStack(alignment: .top, spacing: 0) {
          ForEach(rings) { ring in cell(ring, ringSize: Self.ringSize).frame(maxWidth: .infinity) }
        }
        .frame(maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder private func small(_ rings: [BatteryRingItem]) -> some View {
    if rings.isEmpty {
      emptyState
    } else if rings.count == 1, let ring = rings.first {
      VStack(spacing: 8) {
        BatteryRing(glyph: ring.glyph, percent: ring.percent, charging: ring.charging, size: 68)
        Text("\(ring.percent)%")
          .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
          .contentTransition(.numericText())
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .help(ring.name)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(ring.name), \(ring.percent) percent")
    } else {
      // Two rows of two, each a fixed height, so three or four rings always fit the square.
      Grid(horizontalSpacing: 6, verticalSpacing: 6) {
        ForEach(Array(stride(from: 0, to: rings.count, by: 2)), id: \.self) { start in
          GridRow {
            ForEach(rings[start..<min(start + 2, rings.count)]) { ring in
              cell(ring, ringSize: Self.smallRingSize).frame(maxWidth: .infinity)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func cell(_ ring: BatteryRingItem, ringSize: CGFloat) -> some View {
    VStack(spacing: ringSize < Self.ringSize ? 3 : 5) {
      BatteryRing(glyph: ring.glyph, percent: ring.percent, charging: ring.charging, size: ringSize)
      Text("\(ring.percent)%")
        .font(.system(size: ringSize < Self.ringSize ? 11 : 12, weight: .semibold, design: .rounded)).monospacedDigit()
        .foregroundStyle(IslandInk.primary).contentTransition(.numericText())
    }
    .help(ring.name)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(ring.name), \(ring.percent) percent")
  }

  private var emptyState: some View {
    VStack(spacing: 4) {
      Image(systemName: "battery.0percent").font(.system(size: 22)).foregroundStyle(IslandInk.tertiary)
      Text("No batteries").font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.secondary)
      Text("Connect AirPods or a keyboard.").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One ring of the Batteries widget: the Mac first, then each accessory's batteries in order
/// (AirPods earbuds as one ring when they match, as in `BatteryAccessory`, then the case).
struct BatteryRingItem: Identifiable, Equatable {
  let id: String
  let name: String
  let glyph: String
  let percent: Int
  let charging: Bool?

  static func items(_ devices: [DeviceBattery], limit: Int) -> [BatteryRingItem] {
    let macs = devices.filter { $0.model == .mac }.map {
      BatteryRingItem(id: $0.id, name: $0.accessoryName, glyph: $0.model.glyph(for: nil), percent: $0.percent,
                      charging: $0.charging)
    }
    let accessories = BatteryAccessory.group(devices.filter { $0.model != .mac }).flatMap { accessory in
      accessory.cells.map {
        BatteryRingItem(id: $0.id, name: accessory.name, glyph: $0.glyph, percent: $0.percent, charging: $0.charging)
      }
    }
    return Array((macs + accessories).prefix(limit))
  }
}

/// A horizontal battery: outline, level fill, terminal nub and a bolt while charging.
struct BatteryCapsule: View {
  let percent: Int
  let charging: Bool?
  var width: CGFloat = 52
  var height: CGFloat = 22
  var lowPower = false

  var body: some View {
    let tint = batteryTint(percent: percent, charging: charging, lowPower: lowPower)
    let inner = width - 4
    HStack(spacing: 1.5) {
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
          .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
        RoundedRectangle(cornerRadius: height * 0.32 - 2, style: .continuous)
          .fill(tint)
          .frame(width: max(height * 0.3, inner * CGFloat(min(100, max(0, percent))) / 100), height: height - 4)
          .padding(2)
        if charging == true {
          Image(systemName: "bolt.fill").font(.system(size: height * 0.5, weight: .bold))
            .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 1)
            .frame(maxWidth: .infinity)
        }
      }
      .frame(width: width, height: height)
      Capsule().fill(Color.white.opacity(0.35)).frame(width: 2, height: height * 0.36)
    }
    .accessibilityHidden(true)
  }
}
