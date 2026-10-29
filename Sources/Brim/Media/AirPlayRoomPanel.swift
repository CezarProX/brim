import AVKit
import SwiftUI

/// AirPlay Rooms: where this Mac's sound plays. The current room with its volume, every output to hop
/// to, and the system AirPlay menu for finding speakers that are not connected yet.
/// Fits the island content area (about 560 x 200 pt).
struct AirPlayRoomPanel: View {
  @ObservedObject var model: AirPlayRoomModel = .shared
  static let preferredSize = CGSize(width: 560, height: 200)
  private static let note = Font.system(size: 12, weight: .medium)
  @StateObject private var picker = AirPlayPickerProxy()

  var body: some View {
    HStack(alignment: .top, spacing: IslandSpace.m) {
      roomCard.frame(width: 250)
      outputList
    }
    .padding(.horizontal, IslandSpace.l)
    .frame(maxWidth: Self.preferredSize.width)
    .frame(height: Self.preferredSize.height, alignment: .top)
    .onAppear { model.setActive(true) }
    .onDisappear { model.setActive(false) }
    .preferredColorScheme(.dark)
  }

  // MARK: Current room

  private var roomCard: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      HStack(spacing: IslandSpace.m) {
        Image(systemName: roomSymbol)
          .font(.system(size: 20)).foregroundStyle(model.isAirPlay ? IslandTint.audio : IslandInk.secondary)
          .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: IslandRadius.small).fill(IslandFill.raised))
        VStack(alignment: .leading, spacing: 2) {
          Text("Playing on").font(Self.note).foregroundStyle(IslandInk.secondary)
          Text(model.roomName).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
      volumeRow
    }
    .padding(IslandSpace.m)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(RoundedRectangle(cornerRadius: IslandRadius.medium).fill(IslandFill.subtle))
  }

  private var roomSymbol: String {
    if model.isAirPlay { return "tv.and.hifispeaker.fill" }
    return model.current?.isBluetooth == true ? "headphones" : "laptopcomputer"
  }

  private var volumeBinding: Binding<Double> {
    Binding(get: { Double(model.level ?? 0) }, set: { model.setLevel(Float($0)) })
  }

  private var volumeRow: some View {
    HStack(spacing: IslandSpace.s) {
      Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(IslandInk.secondary).frame(width: 16)
      AudioSlider(value: volumeBinding).disabled(model.level == nil)
      Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(IslandInk.secondary).frame(width: 20)
    }
    .frame(height: 28)
    .opacity(model.level == nil ? 0.4 : 1)
    .help(model.level == nil ? "This output has no volume control" : "Volume")
  }

  // MARK: Outputs

  private var outputList: some View {
    VStack(alignment: .leading, spacing: IslandSpace.xs) {
      HStack {
        Text("Outputs").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
        Spacer(minLength: 0)
        Button { picker.show() } label: { Label("AirPlay…", systemImage: "airplayaudio") }
          .buttonStyle(IslandAppPillStyle(prominent: true, tint: IslandTint.audio))
          .background(AirPlayPickerAnchor(proxy: picker).frame(width: 1, height: 1).opacity(0.01), alignment: .leading)
          .help("Find AirPlay speakers and TVs")
          .accessibilityLabel("Find AirPlay speakers")
      }
      .frame(height: 30)
      outputRows
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var outputRows: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 2) {
        ForEach(model.outputs) { device in row(device) }
        if !model.hasAirPlayOutput { hint }
        if model.switchFailed {
          Text("That output would not switch. Try AirPlay… instead.")
            .font(Self.note).foregroundStyle(Color.orange).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IslandSpace.s)
        }
      }
    }
  }

  private var hint: some View {
    Text("No AirPlay speaker connected. Tap AirPlay… to find one.")
      .font(Self.note).foregroundStyle(IslandInk.tertiary).multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, IslandSpace.s).padding(.top, IslandSpace.xs)
  }

  private func row(_ device: AudioDeviceRef) -> some View {
    let selected = device.uid == model.current?.uid
    return Button { model.select(device) } label: {
      HStack(spacing: IslandSpace.s) {
        Image(systemName: symbol(device)).frame(width: 22)
          .foregroundStyle(selected ? IslandTint.audio : IslandInk.secondary)
        Text(device.name).font(IslandFont.body).lineLimit(1).foregroundStyle(IslandInk.primary)
        Spacer()
        if selected {
          Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(IslandTint.audio)
        }
      }
      .padding(.horizontal, IslandSpace.s).frame(height: 32)
      .background(RoundedRectangle(cornerRadius: IslandRadius.small).fill(selected ? IslandFill.raised : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.98))
    .accessibilityLabel(device.name)
    .accessibilityValue(selected ? "Current output" : "")
  }

  private func symbol(_ device: AudioDeviceRef) -> String {
    if device.isAirPlay { return "airplayaudio" }
    return device.isBluetooth ? "headphones" : "speaker.wave.2.fill"
  }
}

/// Holds the system route picker so a normal SwiftUI pill can open it.
@MainActor
final class AirPlayPickerProxy: ObservableObject {
  weak var view: AVRoutePickerView?

  func show() {
    guard let view else { return }
    if let button = view.subviews.compactMap({ $0 as? NSButton }).first { button.performClick(nil) }
  }
}

/// The (nearly invisible) native AirPlay route button the pill triggers.
struct AirPlayPickerAnchor: NSViewRepresentable {
  let proxy: AirPlayPickerProxy

  func makeNSView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.isRoutePickerButtonBordered = false
    proxy.view = view
    return view
  }
  func updateNSView(_ view: AVRoutePickerView, context: Context) { proxy.view = view }
}

/// The system AirPlay route menu (Apple TVs, HomePods, speakers) as a native button.
struct AirPlayPickerButton: NSViewRepresentable {
  func makeNSView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.isRoutePickerButtonBordered = false
    view.setRoutePickerButtonColor(.white, for: .normal)
    view.setRoutePickerButtonColor(.white, for: .normalHighlighted)
    return view
  }
  func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}
