import SwiftUI

/// The audio outputs beside the player, in the slot Playing Next uses: the island grows to show
/// them, like Control Center's output list, instead of dropping a macOS menu over the notch.
struct PlayerOutputColumn: View {
    @ObservedObject var outputs: AudioOutputModel
    var topInset: CGFloat = 45

    static let rowHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Audio Output")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.secondary)
                .frame(height: 20, alignment: .leading)
                .padding(.top, topInset - 6)
            content.padding(.top, 6)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if outputs.devices.isEmpty {
            Group {
                if outputs.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(outputs.errorMessage ?? "No audio outputs found")
                        .font(.system(size: 13)).foregroundStyle(IslandInk.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(outputs.devices) { device in
                        PlayerOutputRow(name: device.name, symbol: device.playerSymbol,
                                        selected: outputs.selectedID == device.id) { outputs.select(device) }
                            .disabled(outputs.isBusy)
                    }
                    if let error = outputs.errorMessage {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.85),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// One output: its glyph, its name, and Control Center's filled check disc when it is in use.
private struct PlayerOutputRow: View {
    let name: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 22)
                Text(name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                ZStack {
                    Circle().fill(selected ? Color.white : Color.white.opacity(0.22))
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            }
            .foregroundStyle(IslandInk.primary)
            .padding(.horizontal, 10)
            .frame(height: PlayerOutputColumn.rowHeight)
            .background(selected ? IslandFill.selected : hovered ? IslandFill.raised : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.97))
        .onHover { hovered = $0 }
        .animation(NotchMotion.press(reduceMotion: reduceMotion), value: selected)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
