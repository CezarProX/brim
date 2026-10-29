import AppKit
import Metal
import SceneKit
import SwiftUI

/// Whether this Mac can draw the 3D model; without a Metal device the card keeps its SF Symbol.
enum AirPods3DSupport {
  static let isAvailable: Bool = MTLCreateSystemDefaultDevice() != nil
}

/// Renders a still of the model offscreen. Render tests use it (SwiftUI's ImageRenderer cannot
/// capture an `SCNView`), and so can any surface that wants a picture rather than a live view.
enum AirPods3DSnapshot {
  static func image(kind: AirPodsDeviceKind, time: TimeInterval, pixelSize: CGSize, reduceMotion: Bool = false) -> NSImage? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    let scene = AirPods3DScene.make(kind: kind)
    AirPods3DScene.apply(AirPods3DMotion.pose(at: time, reduceMotion: reduceMotion), to: scene)
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
    return renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
  }
}

/// The AirPods glyph on the connect card: the turning 3D model when there is one for this
/// device, otherwise the SF Symbol. `active` is false while the card is hidden, which stops
/// rendering entirely.
struct AirPodsModelView: View {
  let kind: AirPodsDeviceKind?
  let symbol: String
  var size: CGFloat = 60
  var active = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.airPodsVisualStillTime) private var stillTime

  var body: some View {
    Group {
      if let kind, AirPods3DSupport.isAvailable {
        if let stillTime {
          still(kind, time: stillTime)
        } else {
          AirPods3DSceneView(kind: kind, animating: active && !reduceMotion)
        }
      } else {
        Image(systemName: symbol)
          .font(.system(size: size * 0.6, weight: .regular)).foregroundStyle(.white)
          .symbolRenderingMode(.hierarchical)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func still(_ kind: AirPodsDeviceKind, time: TimeInterval) -> some View {
    let pixels = CGSize(width: size * 3, height: size * 3)
    if let image = AirPods3DSnapshot.image(kind: kind, time: time, pixelSize: pixels, reduceMotion: reduceMotion) {
      Image(nsImage: image).resizable().interpolation(.high)
    }
  }
}
