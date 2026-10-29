import SwiftUI

/// Listening modes AirPods can be in. macOS exposes the mode only to Apple's own UI, so the monitor
/// reads it best-effort (see `AirPodsModeProbe`) and the HUD shows it when it can.
enum AirPodsListeningMode: String, CaseIterable, Equatable {
    case off, noiseCancellation, transparency, adaptive

    var title: String {
        switch self {
        case .off: "Off"
        case .noiseCancellation: "Noise Cancellation"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        }
    }
    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .noiseCancellation: "Noise"
        case .transparency: "Transp."
        case .adaptive: "Adaptive"
        }
    }
    var symbol: String {
        switch self {
        case .off: "ear"
        case .noiseCancellation: "ear.badge.waveform"
        case .transparency: "person.wave.2.fill"
        case .adaptive: "sparkles"
        }
    }
    var tint: Color {
        switch self {
        case .off: .white
        case .noiseCancellation: Color(red: 0.4, green: 0.65, blue: 1)
        case .transparency: .orange
        case .adaptive: .mint
        }
    }
}

/// Reads a mode out of a `system_profiler` device entry if macOS ever reports one. On current macOS
/// versions no such key exists, so this returns nil and the mode HUD stays quiet (documented limit).
enum AirPodsModeProbe {
    static let keys = ["device_listeningMode", "device_noiseControlMode", "device_noiseCancellationMode"]

    static func mode(from device: [String: Any]) -> AirPodsListeningMode? {
        for key in keys {
            guard let raw = device[key] as? String else { continue }
            let text = raw.lowercased()
            if text.contains("transparen") { return .transparency }
            if text.contains("adaptive") { return .adaptive }
            if text.contains("cancel") || text.contains("anc") { return .noiseCancellation }
            if text.contains("off") { return .off }
        }
        return nil
    }
}

/// Levels shown on the AirPods connect card.
struct AirPodsBatteries: Equatable {
    var name: String
    var symbol: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// The detected model, which picks the 3D model; cards built without one fall back to `symbol`.
    var model: AccessoryModel? = nil
    /// Bluetooth product ID, which picks macOS's own banner animation for the exact model.
    var productID: Int? = nil
    var hasAny: Bool { left != nil || right != nil || caseLevel != nil }
    var isSingleLevel: Bool { right == nil && caseLevel == nil }
    var kind: AirPodsDeviceKind? { model.flatMap(AirPodsDeviceKind.init(model:)) ?? AirPodsDeviceKind(symbol: symbol) }

    /// SF Symbol for the model: pro, max, 3rd/4th generation or the classic buds.
    static func symbol(for model: AccessoryModel) -> String {
        switch model {
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .airPods3, .airPods4: "airpods.gen3"
        default: "airpods"
        }
    }

    static func isAirPods(_ model: AccessoryModel) -> Bool {
        switch model {
        case .airPods, .airPods3, .airPods4, .airPodsPro, .airPodsMax: true
        default: false
        }
    }

    static func from(_ batteries: [DeviceBattery], accessoryID: String) -> AirPodsBatteries? {
        let parts = batteries.filter { $0.accessoryID == accessoryID }
        guard let first = parts.first, isAirPods(first.model) else { return nil }
        func level(_ part: BatteryPart) -> Int? { parts.first { $0.part == part }?.percent }
        var result = AirPodsBatteries(name: first.accessoryName, symbol: symbol(for: first.model),
                                      left: level(.left), right: level(.right), caseLevel: level(.case), model: first.model,
                                      productID: first.productID)
        // Headband models (Max) report a single level with no part.
        if !result.hasAny, let single = parts.first(where: { $0.part == nil }) { result.left = single.percent }
        return result
    }
}

/// The AirPods card body, laid out like the iPhone connect sheet: the turning 3D model, "Connected"
/// over the device name, and a level ring per bud and the case. `active` is false while the card
/// is hidden so the model stops rendering.
struct AirPodsCardView: View {
    let batteries: AirPodsBatteries
    var detail = "Connected"
    var active = true

    var body: some View {
        HStack(spacing: 12) {
            AirPodsVisual(kind: batteries.kind, productID: batteries.productID, symbol: batteries.symbol, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(detail)).font(IslandFont.label).foregroundStyle(IslandInk.secondary)
                Text(batteries.name).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                // Headband models report one level; it is the headphones', not a left bud's.
                ring(batteries.isSingleLevel ? "" : "L", batteries.left)
                ring("R", batteries.right)
                ring("Case", batteries.caseLevel)
            }
        }
    }

    @ViewBuilder
    private func ring(_ label: String, _ percent: Int?) -> some View {
        if let percent {
            VStack(spacing: 3) {
                ZStack {
                    IslandRing(progress: Double(percent) / 100, tint: batteryTint(percent: percent, charging: nil),
                               lineWidth: 3.5)
                        .padding(1.75)
                    Text("\(percent)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(IslandInk.primary)
                }
                .frame(width: 34, height: 34)
                Text(verbatim: label).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label.isEmpty ? "\(percent) percent" : "\(label) \(percent) percent")
        }
    }
}
