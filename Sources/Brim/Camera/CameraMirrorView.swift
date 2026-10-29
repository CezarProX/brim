import AVFoundation
import AppKit
import SwiftUI

/// Photo Booth's mirror in the island: a live, mirrored picture of you. Nothing is recorded.
struct CameraMirrorView: View {
  @ObservedObject var model: CameraMirrorModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let note = Font.system(size: 12, weight: .medium)
  static let previewHeight: CGFloat = 224

  var body: some View {
    stage
    .task { await model.appear() }
    .onDisappear { model.disappear() }
  }

  private var cameraMenu: some View {
    Menu {
      ForEach(model.cameras) { camera in
        Button { Task { await model.choose(camera.id) } } label: {
          Label(camera.name, systemImage: camera.id == model.selectedID ? "checkmark" : "web.camera")
        }
      }
    } label: {
      Label(model.selectedName ?? "Camera", systemImage: "web.camera").font(Self.note).lineLimit(1)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help("Choose a camera")
  }

  private var stage: some View {
    ZStack {
      CameraPreview(session: model.session, live: model.running)
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
        .opacity(model.running ? 1 : 0)
      if !model.running { card }
      if model.cameras.count > 1 {
        cameraMenu.padding(IslandSpace.s).background(.black.opacity(0.35), in: Capsule())
          .padding(IslandSpace.s).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: Self.previewHeight)
    .glassCard(radius: IslandRadius.large)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.state)
  }

  @ViewBuilder private var card: some View {
    switch model.state {
    case .starting:
      VStack(spacing: IslandSpace.s) {
        ProgressView().controlSize(.small).tint(.white)
        Text("Starting camera…").font(Self.note).foregroundStyle(IslandInk.secondary)
      }
    case .needsAccess:
      message("web.camera", "See yourself on camera",
              "Brim only shows the picture here. Nothing is recorded.",
              action: "Turn On Camera") { Task { await model.allowAccess() } }
    case .denied:
      message("video.slash.fill", "Camera access is off",
              "Allow Brim under Camera in System Settings, then come back.",
              action: "Open Privacy Settings") { Self.openCameraPrivacy() }
    case .noCamera:
      message("web.camera", "No camera found",
              "Connect a camera, or bring an unlocked iPhone nearby to use it.", action: nil) {}
    case .busy:
      message("video.slash.fill", "Camera is in use",
              "Another app is using it. Close that app, then try again.",
              action: "Try Again") { Task { await model.retry() } }
    case .live:
      EmptyView()
    }
  }

  private func message(
    _ symbol: String, _ title: String, _ detail: String, action: String?, perform: @escaping () -> Void
  ) -> some View {
    VStack(spacing: IslandSpace.s) {
      Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(IslandInk.secondary)
      Text(LocalizedStringKey(title)).font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      Text(LocalizedStringKey(detail)).font(Self.note).foregroundStyle(IslandInk.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: 340)
      if let action {
        Button(LocalizedStringKey(action), action: perform)
          .buttonStyle(IslandAppPillStyle(prominent: true, tint: IslandTint.audio))
      }
    }
    .padding(IslandSpace.m)
  }

  static func openCameraPrivacy() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
      NSWorkspace.shared.open(url)
    }
  }
}

private struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession
  let live: Bool

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    view.layer = layer
    return view
  }

  /// The connection only exists once the session has an input, so mirroring is set once it is live.
  func updateNSView(_ view: NSView, context: Context) {
    guard live, let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection,
      connection.isVideoMirroringSupported
    else { return }
    connection.automaticallyAdjustsVideoMirroring = false
    connection.isVideoMirrored = true
  }
}
