import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the LocalSend sheet, Xcode build activity and the settings page to `.renders/`.
@MainActor
@Suite(.serialized)
struct DropletRenderTests {
  private func peer(_ alias: String, model: String, type: String, fingerprint: String) -> LocalSendPeer {
    LocalSendPeer(
      device: LocalSendDevice(
        alias: alias, version: "2.0", deviceModel: model, deviceType: type, fingerprint: fingerprint, port: 53317,
        protocol: "https", download: false, announce: nil),
      host: "192.168.1.20", seenAt: .now)
  }

  private func islandBackdrop<V: View>(_ view: V) -> some View {
    view.padding(.vertical, 14).background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  @Test func rendersTheLocalSendSheet() async throws {
    let model = LocalSendModel()
    model.loadPreview(
      peers: [
        peer("Pixel 9", model: "Google", type: "mobile", fingerprint: "a"),
        peer("Studio Mac", model: "Apple", type: "desktop", fingerprint: "b"),
        peer("Living room PC", model: "Windows", type: "desktop", fingerprint: "c"),
        peer("Web share", model: "Browser", type: "web", fingerprint: "d"),
      ], transfers: [])
    let files = [URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/etc/shells")]
    try await DropletRender.png(islandBackdrop(LocalSendView(model: model, files: files)), size: CGSize(width: 580, height: 200), name: "localsend.png", background: .black)
    var sending = LocalSendTransfer(alias: "Pixel 9")
    sending.phase = .sending
    sending.progress = 0.62
    model.loadPreview(peers: [peer("Pixel 9", model: "Google", type: "mobile", fingerprint: "a")], transfers: [sending])
    try await DropletRender.png(islandBackdrop(LocalSendView(model: model, files: files)), size: CGSize(width: 580, height: 200), name: "localsend-sending.png", background: .black)
    model.loadPreview(peers: [], transfers: [])
    try await DropletRender.png(islandBackdrop(LocalSendView(model: model, files: files)), size: CGSize(width: 580, height: 200), name: "localsend-empty.png", background: .black)
  }

  @Test func rendersXcodeBuildActivity() async throws {
    let model = XcodeBuildModel()
    let size = CGSize(width: 580, height: 112)
    model.preview(.building(project: "Brim", since: .now.addingTimeInterval(-47)))
    try await DropletRender.png(islandBackdrop(XcodeBuildCard(model: model).padding(.horizontal, 12)), size: size, name: "xcode-building.png", background: .black)
    model.preview(.succeeded(project: "Brim", duration: 83, warnings: 2))
    try await DropletRender.png(islandBackdrop(XcodeBuildCard(model: model).padding(.horizontal, 12)), size: size, name: "xcode-succeeded.png", background: .black)
    model.preview(.failed(project: "Brim", duration: 12, errors: 3))
    try await DropletRender.png(islandBackdrop(XcodeBuildCard(model: model).padding(.horizontal, 12)), size: size, name: "xcode-failed.png", background: .black)
    let compact = HStack(spacing: 20) {
      ForEach(0..<3, id: \.self) { index in
        Group {
          switch index {
          case 0: XcodeBuildCompactView(model: { let m = XcodeBuildModel(); m.preview(.building(project: "A", since: .now.addingTimeInterval(-9))); return m }())
          case 1: XcodeBuildCompactView(model: { let m = XcodeBuildModel(); m.preview(.succeeded(project: "A", duration: 83, warnings: 0)); return m }())
          default: XcodeBuildCompactView(model: { let m = XcodeBuildModel(); m.preview(.failed(project: "A", duration: 2, errors: 3)); return m }())
          }
        }
        .padding(.horizontal, 14).frame(height: 32).background(Color.black, in: Capsule())
      }
    }
    try await DropletRender.png(compact, size: CGSize(width: 420, height: 60), name: "xcode-compact.png")
  }

  @Test func rendersTheDropletsSettingsPage() async throws {
    try await DropletRender.png(
      Form { DropletsSettingsSection() }.formStyle(.grouped), size: CGSize(width: 640, height: 1500), name: "droplets-settings.png",
      background: Color(nsColor: .windowBackgroundColor))
  }
}
