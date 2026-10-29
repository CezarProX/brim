import AppKit
import SwiftUI

/// Batteries the way iOS shows them: the connected headphones as the hero with Apple's own glyph
/// for that model, otherwise the Mac with the battery menu's words, otherwise a widget-style row.
struct BatteryActivityView: View {
  @ObservedObject var model: DeviceBatteryModel

  private var accessories: [BatteryAccessory] { BatteryAccessory.group(model.devices) }

  var body: some View {
    let accessories = accessories
    let hero = accessories.first { $0.model.isAudio } ?? (accessories.count == 1 ? accessories.first : nil)
    let others = accessories.filter { $0.id != hero?.id }
    VStack(alignment: .leading, spacing: IslandSpace.l) {
      if let hero, hero.model.isAudio {
        AudioAccessoryHero(accessory: hero)
      } else if let hero, let device = model.devices.first(where: { $0.accessoryID == hero.id }) {
        PowerSourceHero(accessory: hero, device: device)
      } else if accessories.isEmpty {
        Text("No devices are reporting a battery level.")
          .font(IslandFont.body).foregroundStyle(IslandInk.secondary)
      } else {
        BatteryRingRow(accessories: accessories)
      }
      if hero != nil, !others.isEmpty { OtherBatteriesStrip(accessories: others) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.spring(duration: 0.45, bounce: 0.12), value: accessories)
    .onAppear { model.refresh() }
  }
}

/// iOS colors: green, red at 20% and below unless charging, yellow in Low Power Mode.
func batteryTint(percent: Int, charging: Bool?, lowPower: Bool = false) -> Color {
  if charging != true && percent <= 20 { return .red }
  return lowPower ? .yellow : .green
}

/// A level ring with the device (or earbud, or case) glyph inside and a bolt while charging.
struct BatteryRing: View {
  let glyph: String
  let percent: Int
  let charging: Bool?
  var size: CGFloat = 54
  var lowPower = false

  private var lineWidth: CGFloat { size * 0.085 }

  var body: some View {
    ZStack {
      // The stroke is centered on the circle; inset it so scroll views don't clip its outer half.
      IslandRing(progress: Double(percent) / 100, tint: batteryTint(percent: percent, charging: charging, lowPower: lowPower),
                 lineWidth: lineWidth)
        .padding(lineWidth / 2)
      Image(systemName: glyph)
        .font(.system(size: size * 0.36, weight: .regular))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(IslandInk.primary)
        .contentTransition(.symbolEffect(.replace))
      if charging == true {
        Image(systemName: "bolt.fill")
          .font(.system(size: size * 0.2, weight: .bold))
          .foregroundStyle(.green)
          .padding(size * 0.05)
          .background(.black, in: Circle())
          .offset(y: -size / 2 + lineWidth / 2)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(width: size, height: size)
    // Room for the bolt above the ring, reserved always so charging doesn't shift the layout.
    .padding(.top, size * 0.14)
  }
}

private struct AudioAccessoryHero: View {
  let accessory: BatteryAccessory

  var body: some View {
    HStack(alignment: .center, spacing: IslandSpace.l) {
      VStack(alignment: .leading, spacing: IslandSpace.xs) {
        Image(systemName: accessory.glyph)
          .font(.system(size: 44, weight: .light))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(IslandInk.primary)
          .frame(height: 52, alignment: .leading)
        Text(accessory.name).font(IslandFont.title).lineLimit(1)
        Text("Connected").font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: IslandSpace.l) {
        ForEach(accessory.cells) { cell in
          VStack(spacing: 6) {
            BatteryRing(glyph: cell.glyph, percent: cell.percent, charging: cell.charging)
            HStack(spacing: 3) {
              if let label = cell.label {
                Text(label).foregroundStyle(IslandInk.tertiary)
              }
              Text("\(cell.percent)%").monospacedDigit().contentTransition(.numericText())
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(cellName(cell)), \(cell.percent) percent")
        }
      }
    }
  }

  private func cellName(_ cell: BatteryAccessory.Cell) -> String {
    switch cell.label {
    case "L": "Left"
    case "R": "Right"
    default: cell.glyph.contains("case") ? "Case" : accessory.name
    }
  }
}

private extension PowerSourceHero {
  /// Asks macOS for an administrator password (the only way to change Low Power Mode); see LowPowerModeControl.
  var lowPowerButton: some View {
    Button {
      _ = LowPowerModeControl.set(enabled: !lowPower)
      lowPower = BatteryPowerState.isLowPower()
    } label: {
      Label(lowPower ? "Turn off Low Power Mode" : "Turn on Low Power Mode",
            systemImage: lowPower ? "bolt.fill" : "bolt.slash")
        .font(IslandFont.caption.weight(.semibold))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(IslandFill.subtle, in: Capsule())
    }
    .buttonStyle(.plain)
    .help("macOS asks for an administrator password to change this.")
    .padding(.top, 2)
  }
}

private struct PowerSourceHero: View {
  let accessory: BatteryAccessory
  let device: DeviceBattery
  @State private var lowPower = BatteryPowerState.isLowPower()

  var body: some View {
    HStack(spacing: IslandSpace.l) {
      BatteryRing(glyph: accessory.glyph, percent: device.percent, charging: device.charging, size: 76,
                  lowPower: device.model == .mac && lowPower)
      VStack(alignment: .leading, spacing: 2) {
        Text(accessory.name).font(IslandFont.title).lineLimit(1)
        Text("\(device.percent)%")
          .font(IslandFont.display).monospacedDigit()
          .contentTransition(.numericText())
        Text(BatteryStatus.text(device) + (lowPower && device.model == .mac ? " · Low Power Mode" : ""))
          .font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
        if device.model == .mac { lowPowerButton }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .contain)
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = BatteryPowerState.isLowPower()
    }
  }
}

/// The iOS Batteries widget: evenly spaced rings, percentage under each.
private struct BatteryRingRow: View {
  let accessories: [BatteryAccessory]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(accessories.prefix(5)) { accessory in
        VStack(spacing: 6) {
          BatteryRing(glyph: accessory.glyph, percent: accessory.lowest,
                      charging: accessory.cells.contains { $0.charging == true } ? true : nil, size: 58)
          Text("\(accessory.lowest)%")
            .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText())
          Text(accessory.name).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

/// Everything besides the hero, one quiet line: glyph and level.
private struct OtherBatteriesStrip: View {
  let accessories: [BatteryAccessory]

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      ForEach(accessories.prefix(4)) { accessory in
        HStack(spacing: 5) {
          Image(systemName: accessory.glyph).font(.system(size: 11, weight: .medium))
            .symbolRenderingMode(.hierarchical)
          Text("\(accessory.lowest)%").monospacedDigit()
          if accessory.cells.contains(where: { $0.charging == true }) {
            Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
          }
        }
        .font(IslandFont.label)
        .foregroundStyle(accessory.lowest <= 20 ? Color.red : IslandInk.secondary)
        .padding(.horizontal, 9).frame(height: 24)
        .background(IslandFill.subtle, in: Capsule())
        .help(accessory.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessory.name), \(accessory.lowest) percent")
      }
      Spacer(minLength: 0)
    }
  }
}

/// Low Power Mode source for the battery ring; tests replace it so they do not depend on the machine.
enum BatteryPowerState {
  nonisolated(unsafe) static var isLowPower: () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
