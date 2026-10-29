import SwiftUI

/// LocalSend settings: on/off, device name, receiving.
struct LocalSendSettingsSection: View {
  @State private var enabled = AppSettings.shared.localSendEnabled
  @State private var receive = AppSettings.shared.localSendReceiveEnabled
  @State private var alias = AppSettings.shared.localSendAlias
  @ObservedObject private var model = LocalSendModel.shared

  var body: some View {
    SettingsSection("LocalSend") {
      Toggle("Send files to nearby devices with LocalSend", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.localSendEnabled = value
          if value { Task { await model.start() } } else { model.stop() }
        }
      if enabled {
        HStack {
          Text("This Mac appears as")
          TextField("Name", text: $alias).textFieldStyle(.roundedBorder).frame(width: 200)
            .onSubmit { AppSettings.shared.localSendAlias = alias; Task { model.stop(); await model.start() } }
        }
        Toggle("Receive files (asks before accepting, saves to Downloads)", isOn: $receive)
          .onChange(of: receive) { _, value in AppSettings.shared.localSendReceiveEnabled = value }
        if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        else if model.isRunning { Text("Listening. \(model.peers.count) device\(model.peers.count == 1 ? "" : "s") found.").font(.footnote).foregroundStyle(.secondary) }
      }
      Text("Uses the open LocalSend protocol over your local network only: multicast discovery, then an encrypted connection straight to the other device. macOS asks for Local Network access the first time. Nothing goes through the internet.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
