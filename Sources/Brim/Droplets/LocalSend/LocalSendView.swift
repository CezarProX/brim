import SwiftUI

/// The LocalSend sheet shown inside the open island (about 560 x 200 pt): nearby devices as
/// cards; tapping one sends the files. Opened from the tray's "LocalSend" quick action.
struct LocalSendView: View {
  @ObservedObject var model: LocalSendModel
  let files: [URL]
  var onClose: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      header
      content
    }
    .padding(.horizontal, IslandSpace.m)
    .task { if AppSettings.shared.localSendEnabled { await model.start() } }
    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: model.peers)
    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: model.transfers)
  }

  private var header: some View {
    HStack(spacing: IslandSpace.s) {
      Image(systemName: "paperplane.fill").foregroundStyle(.cyan).font(.system(size: 14, weight: .semibold))
      VStack(alignment: .leading, spacing: 1) {
        Text("LocalSend").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
        Text(Self.summary(files)).font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
      }
      Spacer()
      Button { model.refresh() } label: {
        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
          .foregroundStyle(IslandInk.secondary).frame(width: 26, height: 26)
          .background(IslandFill.subtle, in: Circle())
      }
      .buttonStyle(IslandPressStyle()).accessibilityLabel("Look for devices again")
    }
  }

  @ViewBuilder private var content: some View {
    if !model.isRunning {
      notRunning
    } else if model.peers.isEmpty && model.transfers.isEmpty {
      empty
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: IslandSpace.s) {
          ForEach(model.peers) { peer in deviceCard(peer) }
        }
      }
      if !model.transfers.isEmpty { transferList }
    }
  }

  private var notRunning: some View {
    VStack(spacing: IslandSpace.s) {
      Text(model.errorMessage ?? "LocalSend is off. Turn it on to find devices on your network.")
        .font(IslandFont.body).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
      Button("Turn on LocalSend") {
        AppSettings.shared.localSendEnabled = true
        Task { await model.start() }
      }
      .buttonStyle(.borderedProminent).controlSize(.small)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
  }

  private var empty: some View {
    VStack(spacing: 6) {
      ProgressView().controlSize(.small)
      Text("Looking for devices").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      Text("Open LocalSend on the other device, on the same Wi-Fi.")
        .font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
  }

  private func deviceCard(_ peer: LocalSendPeer) -> some View {
    Button { model.send(files, to: peer) } label: {
      VStack(spacing: 6) {
        Image(systemName: peer.device.symbol).font(.system(size: 24, weight: .regular))
          .foregroundStyle(.cyan).frame(height: 30)
        Text(peer.device.alias).font(IslandFont.label.weight(.semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
        Text(peer.device.deviceModel ?? peer.host).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      }
      .frame(width: 104, height: 82)
      .glassCard(radius: IslandRadius.medium)
    }
    .buttonStyle(IslandPressStyle())
    .disabled(files.isEmpty)
    .accessibilityLabel("Send to \(peer.device.alias)")
  }

  private var transferList: some View {
    VStack(spacing: 4) {
      ForEach(model.transfers.suffix(2)) { transfer in
        HStack(spacing: IslandSpace.s) {
          Image(systemName: Self.symbol(transfer.phase)).foregroundStyle(Self.tint(transfer.phase)).frame(width: 16)
          Text(transfer.alias).font(IslandFont.label).foregroundStyle(IslandInk.primary)
          switch transfer.phase {
          case .waiting: Text("Waiting for them to accept").font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
          case .sending: ProgressView(value: transfer.progress).tint(.cyan).frame(maxWidth: 160)
          case .done: Text("Sent").font(IslandFont.caption).foregroundStyle(.green)
          case .failed(let message): Text(message).font(IslandFont.caption).foregroundStyle(.orange).lineLimit(1)
          }
          Spacer()
        }
      }
    }
  }

  static func summary(_ files: [URL]) -> String {
    guard !files.isEmpty else { return "No files selected" }
    let bytes = files.reduce(Int64(0)) {
      $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? NSNumber)?.int64Value ?? 0)
    }
    return "\(files.count) file\(files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
  }

  private static func symbol(_ phase: LocalSendTransfer.Phase) -> String {
    switch phase {
    case .waiting: "hourglass"
    case .sending: "arrow.up.circle.fill"
    case .done: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  private static func tint(_ phase: LocalSendTransfer.Phase) -> Color {
    switch phase {
    case .waiting: .gray
    case .sending: .cyan
    case .done: .green
    case .failed: .orange
    }
  }
}
