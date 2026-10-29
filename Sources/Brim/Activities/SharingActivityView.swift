import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Share: drop files, then send them with AirDrop, the share sheet or a nearby LocalSend device.
/// A link pasted on the right becomes a QR code for a phone.
struct SharingActivityView: View {
  @ObservedObject var model: SharingActivityModel
  @ObservedObject var localSend: LocalSendModel = .shared
  @State private var targeted = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var tint: Color { IslandTint.color(for: .transfer) }
  private static let note = Font.system(size: 12, weight: .medium)
  private var hasFiles: Bool { !model.files.isEmpty }

  var body: some View {
    HStack(alignment: .top, spacing: IslandSpace.m) {
      stage.frame(maxWidth: .infinity)
      qrCard.frame(width: 168)
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.files)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.link)
  }

  // MARK: Files

  private var stage: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      dropZone
      if hasFiles { actions }
      if let notice = model.notice {
        Text(notice).font(Self.note).foregroundStyle(Color.orange).lineLimit(2)
      }
      if hasFiles && !localSend.peers.isEmpty { nearby }
    }
  }

  private var dropZone: some View {
    VStack(spacing: IslandSpace.s) {
      if hasFiles { fileRows } else { emptyZone }
    }
    .padding(IslandSpace.m)
    .frame(maxWidth: .infinity, minHeight: hasFiles ? 96 : 150)
    .background(
      targeted ? tint.opacity(0.14) : IslandFill.subtle,
      in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
        .strokeBorder(targeted ? tint : Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }
    .scaleEffect(targeted && !reduceMotion ? 1.02 : 1)
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: targeted)
    .onDrop(of: FileDropLoader.types, isTargeted: $targeted, perform: model.drop)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Drop files here")
  }

  private var emptyZone: some View {
    VStack(spacing: IslandSpace.s) {
      Image(systemName: "square.and.arrow.up.circle.fill")
        .font(.system(size: 38, weight: .regular)).symbolRenderingMode(.hierarchical)
        .foregroundStyle(targeted ? tint : IslandInk.secondary)
        .symbolEffect(.bounce, value: targeted)
      Text(targeted ? "Drop to share" : "Drop files here").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      Text("Then send them with AirDrop or any share option").font(Self.note)
        .foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
      Button("Choose Files…", action: model.chooseFiles).buttonStyle(IslandAppPillStyle())
    }
  }

  private var fileRows: some View {
    VStack(spacing: 2) {
      ForEach(model.files.prefix(3), id: \.self) { url in
        HStack(spacing: IslandSpace.s) {
          Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
          Text(url.lastPathComponent).font(IslandFont.body).foregroundStyle(IslandInk.primary).lineLimit(1)
          Spacer(minLength: 0)
          Button { model.remove(url) } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(IslandInk.tertiary)
              .frame(width: 28, height: 28).contentShape(Rectangle())
          }
          .buttonStyle(.plain).help("Remove").accessibilityLabel("Remove \(url.lastPathComponent)")
        }
        .frame(height: 30)
        .transition(.islandDrop)
      }
      if model.files.count > 3 {
        Text("+\(model.files.count - 3) more").font(Self.note).foregroundStyle(IslandInk.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var actions: some View {
    HStack(spacing: IslandSpace.s) {
      Button { model.airDrop() } label: { Label("AirDrop", systemImage: "airplayaudio.circle.fill").labelStyle(.titleAndIcon) }
        .buttonStyle(IslandAppPillStyle(prominent: true, tint: tint))
        .help("Send with AirDrop")
      NativeShareButton(items: model.files, onPresentationChange: { model.isPresenting = $0 })
        .frame(width: 84, height: 28)
        .background(IslandFill.raised, in: Capsule())
      Button("Add…", action: model.chooseFiles).buttonStyle(IslandAppPillStyle())
      Spacer(minLength: 0)
      Button("Clear", action: model.clear).buttonStyle(IslandAppPillStyle())
    }
    .transition(.opacity)
  }

  /// LocalSend devices found on the network (only when LocalSend is turned on): one tap sends.
  private var nearby: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Nearby with LocalSend").font(Self.note).foregroundStyle(IslandInk.secondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: IslandSpace.s) {
          ForEach(localSend.peers) { peer in
            Button { localSend.send(model.files, to: peer) } label: {
              Label(peer.device.alias, systemImage: "paperplane.fill")
            }
            .buttonStyle(IslandAppPillStyle())
          }
        }
      }
    }
  }

  // MARK: Link to QR

  private var qrCard: some View {
    VStack(spacing: IslandSpace.s) {
      ZStack {
        if let image = SharingActivityModel.qrCode(for: model.link) {
          Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            .padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
          VStack(spacing: 6) {
            Image(systemName: "qrcode").font(.system(size: 34, weight: .light)).foregroundStyle(IslandInk.tertiary)
            Text("Paste a link to scan it with your phone").font(Self.note).foregroundStyle(IslandInk.secondary)
              .multilineTextAlignment(.center)
          }
        }
      }
      .frame(width: 128, height: 118)
      HStack(spacing: 6) {
        Image(systemName: "link").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
        TextField("Paste a link", text: $model.link)
          .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
      }
      .padding(.horizontal, IslandSpace.s).frame(height: 28)
      .background(IslandFill.raised, in: Capsule())
    }
    .padding(IslandSpace.m)
    .frame(maxWidth: .infinity)
    .glassCard(radius: IslandRadius.large)
  }
}
