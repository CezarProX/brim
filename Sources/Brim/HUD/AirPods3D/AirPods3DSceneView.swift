import AppKit
import SceneKit
import SwiftUI

/// Hosts the live `SCNView`. It renders only while `animating`; otherwise it holds the resting
/// pose and SceneKit draws nothing further, so a hidden or Reduce Motion card costs no GPU time.
struct AirPods3DSceneView: NSViewRepresentable {
  let kind: AirPodsDeviceKind
  let animating: Bool

  func makeCoordinator() -> AirPods3DAnimator { AirPods3DAnimator() }

  func makeNSView(context: Context) -> SCNView {
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 60, height: 60), options: nil)
    view.backgroundColor = .clear
    view.wantsLayer = true
    view.layer?.isOpaque = false
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 60
    view.allowsCameraControl = false
    view.isJitteringEnabled = false
    view.rendersContinuously = false
    view.delegate = context.coordinator
    context.coordinator.attach(scene: AirPods3DScene.make(kind: kind), kind: kind, to: view)
    context.coordinator.setAnimating(animating, in: view)
    return view
  }

  func updateNSView(_ view: SCNView, context: Context) {
    if context.coordinator.kind != kind {
      context.coordinator.attach(scene: AirPods3DScene.make(kind: kind), kind: kind, to: view)
    }
    context.coordinator.setAnimating(animating, in: view)
  }

  static func dismantleNSView(_ view: SCNView, coordinator: AirPods3DAnimator) {
    coordinator.setAnimating(false, in: view)
    view.delegate = nil
    view.scene = nil
  }
}

/// Drives the pose from `AirPods3DMotion` on SceneKit's render loop. Each time animation starts
/// the intro plays again from the beginning.
final class AirPods3DAnimator: NSObject, SCNSceneRendererDelegate {
  private(set) var kind: AirPodsDeviceKind?
  private(set) var isAnimating = false
  private let lock = NSLock()
  private var startTime: TimeInterval?
  private weak var scene: SCNScene?

  func attach(scene: SCNScene, kind: AirPodsDeviceKind, to view: SCNView) {
    self.kind = kind
    self.scene = scene
    view.scene = scene
    view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
  }

  func setAnimating(_ animating: Bool, in view: SCNView) {
    guard animating != isAnimating || view.isPlaying != animating else { return }
    isAnimating = animating
    lock.withLock { startTime = nil }
    if !animating, let scene { AirPods3DScene.apply(AirPods3DMotion.restPose, to: scene) }
    view.scene?.isPaused = !animating
    view.isPlaying = animating
  }

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    guard let scene = renderer.scene else { return }
    let elapsed: TimeInterval = lock.withLock {
      if startTime == nil { startTime = time }
      return time - (startTime ?? time)
    }
    guard renderer.isPlaying else { return }
    AirPods3DScene.apply(AirPods3DMotion.pose(at: elapsed), to: scene)
  }
}
