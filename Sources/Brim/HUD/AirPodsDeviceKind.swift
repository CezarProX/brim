import Foundation

/// Which AirPods the card is showing, which picks its picture. Beats and unknown headphones have none;
/// the card keeps the SF Symbol for them.
enum AirPodsDeviceKind: String, CaseIterable, Equatable, Sendable {
  case original, gen3, gen4, pro, max

  init?(model: AccessoryModel) {
    switch model {
    case .airPods: self = .original
    case .airPods3: self = .gen3
    case .airPods4: self = .gen4
    case .airPodsPro: self = .pro
    case .airPodsMax: self = .max
    default: return nil
    }
  }

  /// Best guess from the card's SF Symbol, for cards built without a model.
  init?(symbol: String) {
    switch symbol {
    case "airpods": self = .original
    case "airpods.gen3": self = .gen3
    case "airpodspro": self = .pro
    case "airpodsmax": self = .max
    default: return nil
    }
  }

  var isEarbuds: Bool { self != .max }
}
