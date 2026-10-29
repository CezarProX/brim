import AppKit
import SwiftUI

/// Batteries, opened: one row per physical device (the Mac, AirPods with both buds and the case,
/// keyboard, mouse…), lowest level colored like iOS, with a refresh and a way to pair more.
struct DevicesAppView: View {
  @ObservedObject var model: DeviceBatteryModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var accessories: [BatteryAccessory] { BatteryAccessory.group(model.devices) }

  static func openBluetoothSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
      NSWorkspace.shared.open(url)
    }
  }

  var body: some View {
    let accessories = accessories
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      if !model.hasLoaded && accessories.isEmpty {
        status(symbol: nil, title: L10n.tr("Looking for devices…"), detail: nil)
      } else if accessories.isEmpty {
        empty
      } else {
        list(accessories)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1), value: accessories)
    .onAppear { model.refresh() }
  }

  // MARK: List

  private func list(_ accessories: [BatteryAccessory]) -> some View {
    VStack(spacing: IslandSpace.s) {
      ScrollView {
        VStack(spacing: 6) {
          ForEach(accessories) { accessory in
            row(accessory)
          }
        }
        .padding(.vertical, 1)
      }
      .scrollIndicators(.hidden)
      HStack(spacing: IslandSpace.s) {
        IslandAppButton(title: L10n.tr("Bluetooth Settings"), symbol: "gearshape") { Self.openBluetoothSettings() }
        IslandAppButton(
          title: model.isRefreshing ? L10n.tr("Refreshing…") : L10n.tr("Refresh"), symbol: "arrow.clockwise"
        ) { model.refresh() }
        .disabled(model.isRefreshing)
      }
      .frame(height: 32)
    }
  }

  private func row(_ accessory: BatteryAccessory) -> some View {
    let device = model.devices.first { $0.accessoryID == accessory.id }
    let low = accessory.lowest
    let charging = accessory.cells.contains { $0.charging == true }
    return HStack(spacing: IslandSpace.m) {
      BatteryRing(glyph: accessory.glyph, percent: low, charging: charging ? true : nil, size: 38)
        .padding(.top, -4)
      VStack(alignment: .leading, spacing: 1) {
        Text(accessory.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Text(statusText(accessory, device: device))
          .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      Spacer(minLength: IslandSpace.s)
      if accessory.cells.count > 1 {
        HStack(spacing: 6) {
          ForEach(accessory.cells) { cell in cellPill(cell, in: accessory) }
        }
      } else {
        Text("\(low)%").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
          .foregroundStyle(batteryTint(percent: low, charging: charging ? true : nil))
          .contentTransition(.numericText())
      }
    }
    .padding(.horizontal, IslandSpace.m).padding(.vertical, 6)
    .frame(maxWidth: .infinity, minHeight: 48)
    .islandAppCard()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessory.name)
    .accessibilityValue(accessory.cells.map { "\(cellName($0, in: accessory)) \($0.percent) percent" }.joined(separator: ", "))
  }

  private func statusText(_ accessory: BatteryAccessory, device: DeviceBattery?) -> String {
    if let device, device.model == .mac { return BatteryStatus.text(device) }
    if accessory.cells.contains(where: { $0.charging == true }) { return L10n.tr("Charging") }
    return L10n.tr("Connected")
  }

  private func cellPill(_ cell: BatteryAccessory.Cell, in accessory: BatteryAccessory) -> some View {
    HStack(spacing: 4) {
      Text(cellName(cell, in: accessory)).foregroundStyle(IslandInk.tertiary)
      Text("\(cell.percent)%").monospacedDigit()
        .foregroundStyle(batteryTint(percent: cell.percent, charging: cell.charging))
    }
    .font(.system(size: 12, weight: .semibold, design: .rounded))
    .padding(.horizontal, 8).frame(height: 26)
    .background(IslandFill.subtle, in: Capsule())
  }

  /// "Left", "Right", "Case"; a single reading carries no label.
  private func cellName(_ cell: BatteryAccessory.Cell, in accessory: BatteryAccessory) -> String {
    switch cell.label {
    case "L": L10n.tr("Left")
    case "R": L10n.tr("Right")
    default:
      if cell.glyph.contains("case") { L10n.tr("Case") } else { accessory.model.isAudio ? L10n.tr("Earbuds") : L10n.tr("Battery") }
    }
  }

  // MARK: Empty

  private var empty: some View {
    VStack(spacing: IslandSpace.m) {
      Spacer(minLength: 0)
      status(
        symbol: "airpods.gen3", title: L10n.tr("No accessories reporting a battery"),
        detail: L10n.tr("Connect AirPods, a keyboard, a mouse or a trackpad. Their battery appears here."))
      IslandAppButton(title: L10n.tr("Open Bluetooth Settings"), symbol: "gearshape", style: .prominent(.white)) {
        Self.openBluetoothSettings()
      }
      .frame(width: 220)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private func status(symbol: String?, title: String, detail: String?) -> some View {
    VStack(spacing: 4) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 30, weight: .light))
          .symbolRenderingMode(.hierarchical).foregroundStyle(IslandInk.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
      Text(title).font(.system(size: 13, weight: .semibold))
      if let detail {
        Text(detail).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
  }
}
