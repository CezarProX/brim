import Foundation

/// Which piece of a multi-battery accessory a level belongs to.
enum BatteryPart: String, CaseIterable, Sendable {
  case left, right, `case`
}

enum BeatsFamily: String, CaseIterable, Sendable {
  case powerbeatsPro, fitPro, studioBudsPlus, studioBuds, soloBuds, powerbeats, pill, headphones, earphones
}

/// The exact device, so the page can draw Apple's own glyph for it instead of a generic earbud.
enum AccessoryModel: Equatable, Sendable {
  case mac
  case airPods, airPods3, airPods4, airPodsPro, airPodsMax
  case beats(BeatsFamily)
  case headphones, magicMouse, mouse, keyboard, trackpad, gameController, speaker, other

  static let appleVendorID = 0x004C

  /// Bluetooth product IDs macOS reports in `system_profiler SPBluetoothDataType`.
  private static let appleProductIDs: [Int: AccessoryModel] = [
    0x2002: .airPods, 0x200F: .airPods, 0x2013: .airPods3, 0x2019: .airPods4, 0x201B: .airPods4,
    0x200E: .airPodsPro, 0x2014: .airPodsPro, 0x2024: .airPodsPro, 0x2027: .airPodsPro, 0x2028: .airPodsPro,
    0x200A: .airPodsMax,
  ]

  /// Product ID first (survives renaming), then the device name, then its Bluetooth type.
  static func identify(productID: Int?, vendorID: Int?, name: String, type: String?) -> AccessoryModel {
    if vendorID == appleVendorID, let productID, let model = appleProductIDs[productID] { return model }
    let name = name.lowercased()
    let type = type?.lowercased() ?? ""
    if name.contains("airpods max") { return .airPodsMax }
    if name.contains("airpods pro") { return .airPodsPro }
    if name.contains("airpods") { return vendorID == nil || vendorID == appleVendorID ? .airPods : .headphones }
    if let family = beatsFamily(name) { return .beats(family) }
    if name.contains("magic mouse") { return .magicMouse }
    if name.contains("trackpad") { return .trackpad }
    if type.contains("mouse") || name.contains("mouse") || name.contains("mx master") || name.contains("mx anywhere") {
      return .mouse
    }
    if type.contains("keyboard") || name.contains("keyboard") { return .keyboard }
    if type.contains("gamepad") || type.contains("joystick") || name.contains("controller") { return .gameController }
    if type.contains("headphone") || type.contains("headset") { return .headphones }
    if type.contains("stereo") || type.contains("speaker") || type.contains("portable audio") { return .speaker }
    return .other
  }

  private static func beatsFamily(_ name: String) -> BeatsFamily? {
    guard name.contains("beats") else { return nil }
    let checks: [(String, BeatsFamily)] = [
      ("powerbeats pro", .powerbeatsPro), ("fit pro", .fitPro), ("studio buds +", .studioBudsPlus),
      ("studio buds+", .studioBudsPlus), ("studio buds plus", .studioBudsPlus), ("studio buds", .studioBuds),
      ("solo buds", .soloBuds), ("powerbeats", .powerbeats), ("pill", .pill), ("flex", .earphones),
      ("beatsx", .earphones), ("beats x", .earphones),
    ]
    return checks.first { name.contains($0.0) }?.1 ?? .headphones
  }

  var isAudio: Bool {
    switch self {
    case .airPods, .airPods3, .airPods4, .airPodsPro, .airPodsMax, .beats, .headphones, .speaker: true
    default: false
    }
  }

  /// Apple's SF Symbol for the whole device (`part == nil`) or one of its batteries.
  func glyph(for part: BatteryPart?) -> String {
    switch self {
    case .mac: return "macbook"
    case .airPods: return Self.buds(part, whole: "airpods", left: "airpod.left", right: "airpod.right",
                                   case: "airpods.chargingcase.fill")
    case .airPods3: return Self.buds(part, whole: "airpods.gen3", left: "airpod.gen3.left", right: "airpod.gen3.right",
                                    case: "airpods.gen3.chargingcase.wireless.fill")
    case .airPods4: return Self.buds(part, whole: "airpods.gen4", left: "airpods.gen4.left", right: "airpods.gen4.right",
                                    case: "airpods.gen4.chargingcase.wireless.fill")
    case .airPodsPro: return Self.buds(part, whole: "airpodspro", left: "airpodpro.left", right: "airpodpro.right",
                                      case: "airpodspro.chargingcase.wireless.fill")
    case .airPodsMax: return "airpodsmax"
    case .beats(let family): return Self.beats(family, part)
    case .headphones: return "headphones"
    case .magicMouse: return "magicmouse.fill"
    case .mouse: return "computermouse.fill"
    case .keyboard: return "keyboard.fill"
    case .trackpad: return "rectangle.and.hand.point.up.left.fill"
    case .gameController: return "gamecontroller.fill"
    case .speaker: return "hifispeaker.fill"
    case .other: return "battery.100percent"
    }
  }

  private static func buds(_ part: BatteryPart?, whole: String, left: String, right: String, case chargingCase: String)
    -> String
  {
    switch part {
    case nil: whole
    case .left: left
    case .right: right
    case .case: chargingCase
    }
  }

  private static func beats(_ family: BeatsFamily, _ part: BatteryPart?) -> String {
    switch family {
    case .powerbeatsPro: buds(part, whole: "beats.powerbeats.pro", left: "beats.powerbeats.pro.left",
                              right: "beats.powerbeats.pro.right", case: "beats.powerbeats.pro.chargingcase")
    case .fitPro: buds(part, whole: "beats.fitpro", left: "beats.fitpro.left", right: "beats.fitpro.right",
                       case: "beats.fitpro.chargingcase")
    case .studioBudsPlus: buds(part, whole: "beats.studiobudsplus", left: "beats.studiobudsplus.left",
                               right: "beats.studiobudsplus.right", case: "beats.studiobudsplus.chargingcase")
    case .studioBuds: buds(part, whole: "beats.studiobuds", left: "beats.studiobuds.left",
                           right: "beats.studiobuds.right", case: "beats.studiobuds.chargingcase")
    case .soloBuds: buds(part, whole: "beats.solobuds", left: "beats.solobuds.left", right: "beats.solobuds.right",
                         case: "beats.solobuds.chargingcase")
    case .powerbeats: buds(part, whole: "beats.powerbeats", left: "beats.powerbeats.left",
                           right: "beats.powerbeats.right", case: "beats.powerbeats")
    case .pill: "beats.pill.fill"
    case .headphones: "beats.headphones"
    case .earphones: "beats.earphones"
    }
  }
}

/// One physical device on the Batteries page: AirPods are one accessory with earbud and case levels.
struct BatteryAccessory: Identifiable, Equatable {
  struct Cell: Identifiable, Equatable {
    let id: String
    /// "L"/"R" when the earbuds differ; nil for a combined pair, the case or a single battery.
    let label: String?
    let glyph: String
    let percent: Int
    let charging: Bool?
  }

  let id: String
  let name: String
  let model: AccessoryModel
  let cells: [Cell]

  var glyph: String { model.glyph(for: nil) }
  var lowest: Int { cells.map(\.percent).min() ?? 0 }

  /// Mac first, then audio, then everything else, keeping discovery order within each group.
  static func group(_ devices: [DeviceBattery]) -> [BatteryAccessory] {
    var order: [String] = []
    var members: [String: [DeviceBattery]] = [:]
    for device in devices {
      if members[device.accessoryID] == nil { order.append(device.accessoryID) }
      members[device.accessoryID, default: []].append(device)
    }
    let accessories = order.compactMap { id -> BatteryAccessory? in
      guard let parts = members[id], let first = parts.first else { return nil }
      return BatteryAccessory(id: id, name: first.accessoryName, model: first.model, cells: cells(parts, model: first.model))
    }
    func rank(_ model: AccessoryModel) -> Int { model == .mac ? 0 : model.isAudio ? 1 : 2 }
    return accessories.enumerated().sorted { lhs, rhs in
      (rank(lhs.element.model), lhs.offset) < (rank(rhs.element.model), rhs.offset)
    }.map(\.element)
  }

  private static func cells(_ parts: [DeviceBattery], model: AccessoryModel) -> [Cell] {
    let left = parts.first { $0.part == .left }
    let right = parts.first { $0.part == .right }
    var result: [Cell] = []
    if let left, let right, left.percent == right.percent {
      // iOS shows one earbud reading when both sides agree.
      result.append(Cell(id: left.id, label: nil, glyph: model.glyph(for: nil), percent: left.percent,
                         charging: left.charging == true || right.charging == true ? true : left.charging))
    } else {
      for bud in [left, right].compactMap({ $0 }) {
        result.append(Cell(id: bud.id, label: bud.part == .left ? "L" : "R", glyph: bud.symbol,
                           percent: bud.percent, charging: bud.charging))
      }
    }
    for other in parts where other.part != .left && other.part != .right {
      result.append(Cell(id: other.id, label: nil, glyph: other.symbol, percent: other.percent, charging: other.charging))
    }
    return result
  }
}
