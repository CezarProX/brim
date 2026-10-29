import Combine
import SwiftUI

@MainActor
final class PlayerVolumeModel: ObservableObject {
    @Published private(set) var state: SystemVolumeControl.State?
    @Published private(set) var errorMessage: String?
    var level: Double { state.map { $0.muted ? 0 : $0.level } ?? 0 }
    var isAvailable: Bool { state != nil }
    private let read: () -> SystemVolumeControl.State?
    private let write: (Double) -> Bool
    private let unmute: () -> Bool

    init(read: @escaping () -> SystemVolumeControl.State? = SystemVolumeControl.read,
         write: @escaping (Double) -> Bool = SystemVolumeControl.setLevel,
         unmute: @escaping () -> Bool = { SystemVolumeControl.setMuted(false) }) {
        self.read = read
        self.write = write
        self.unmute = unmute
        state = read()
    }

    func refresh() { state = read() }

    func setLevel(_ value: Double) {
        guard value.isFinite, let before = state else { return }
        let target = HUDLevelMath.clamp(value)
        guard write(target) else { failedWrite(); return }
        if before.muted && target > 0, !unmute() { failedWrite(); return }
        errorMessage = nil
        state = read() ?? .init(level: target, muted: before.muted && target == 0)
    }

    private func failedWrite() {
        state = read()
        errorMessage = L10n.tr("This audio output does not allow volume changes.")
    }
}

/// The same output-volume row in Home and the full player. Hardware changes are read back;
/// unsupported HDMI/AirPlay outputs show an unavailable control rather than a fake volume.
@MainActor
struct PlayerVolumeSlider: View {
    @StateObject private var model: PlayerVolumeModel
    @State private var editing = false
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(model: PlayerVolumeModel? = nil) {
        _model = StateObject(wrappedValue: model ?? PlayerVolumeModel())
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "speaker.fill").font(.system(size: 9))
            AudioSlider(value: Binding(get: { model.level }, set: model.setLevel),
                        onEditingChanged: { editing = $0 })
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9))
        }
        .foregroundStyle(IslandInk.secondary)
        .frame(height: 18)
        .disabled(!model.isAvailable)
        .opacity(model.isAvailable ? 1 : 0.4)
        .help(model.errorMessage ?? L10n.tr("Volume"))
        .onReceive(refresh) { _ in if !editing { model.refresh() } }
    }
}
