import AppKit
import SceneKit

/// Assembles the scene for one model: model → pose (intro scale/lean) → turntable (yaw), framed
/// by a telephoto camera and lit by `AirPods3DStudio`.
enum AirPods3DScene {
  static let fieldOfView: CGFloat = 22
  /// Camera elevation above the model's center, radians.
  static let cameraElevation: CGFloat = 0.14
  /// Breathing room around the turning silhouette; the Max's wide cups need more.
  static func margin(for kind: AirPodsDeviceKind) -> CGFloat { kind == .max ? 1.12 : 0.96 }

  static func make(kind: AirPodsDeviceKind) -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    let model = makeModel(kind)
    let box = bounds(of: model)
    let center = SCNVector3((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2, (box.min.z + box.max.z) / 2)
    model.position = SCNVector3(-center.x, -center.y, -center.z)
    let pose = SCNNode()
    pose.name = "pose"
    pose.addChildNode(model)
    let turntable = SCNNode()
    turntable.name = "turntable"
    turntable.addChildNode(pose)
    scene.rootNode.addChildNode(turntable)
    scene.rootNode.addChildNode(camera(fitting: box, margin: margin(for: kind)))
    AirPods3DStudio.light(scene)
    apply(AirPods3DMotion.restPose, to: scene)
    return scene
  }

  static func makeModel(_ kind: AirPodsDeviceKind) -> SCNNode {
    if kind == .max { return AirPodsMaxBuilder.make() }
    let spec = AirPodsBudSpec.spec(for: kind)
    let pair = SCNNode()
    pair.name = "pair"
    for side in [CGFloat(1), -1] {
      let bud = AirPodsBudBuilder.makeBud(spec, side: side)
      bud.position = SCNVector3(-side * spec.spacing, 0, 0)
      pair.addChildNode(bud)
    }
    return pair
  }

  static func apply(_ pose: AirPods3DMotion.Pose, to scene: SCNScene) {
    guard let turntable = scene.rootNode.childNode(withName: "turntable", recursively: false),
          let poseNode = turntable.childNode(withName: "pose", recursively: false) else { return }
    turntable.eulerAngles.y = pose.yaw
    poseNode.scale = SCNVector3(pose.scale, pose.scale, pose.scale)
    poseNode.eulerAngles.x = pose.pitch
  }

  /// Fits the model's turning silhouette (its radius around the vertical axis) in a square view.
  private static func camera(fitting box: (min: SCNVector3, max: SCNVector3), margin: CGFloat) -> SCNNode {
    let halfWidth = max(abs(box.max.x - box.min.x), abs(box.max.z - box.min.z)) / 2
    let radius = hypot(box.max.x - box.min.x, box.max.z - box.min.z) / 2
    let halfHeight = (box.max.y - box.min.y) / 2
    let extent = max(halfWidth, radius * 0.9, halfHeight) * margin
    let distance = extent / tan(fieldOfView / 2 * .pi / 180) + radius * 0.55
    let camera = SCNCamera()
    camera.fieldOfView = fieldOfView
    camera.zNear = 0.1
    camera.zFar = Double(distance * 3)
    camera.wantsHDR = false
    let node = SCNNode()
    node.name = "camera"
    node.camera = camera
    node.position = SCNVector3(0, distance * sin(cameraElevation), distance * cos(cameraElevation))
    node.eulerAngles.x = -cameraElevation
    return node
  }

  /// Axis-aligned bounds of every geometry under `node`, in `node`'s own space.
  static func bounds(of node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
    var low = SCNVector3(CGFloat.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
    var high = SCNVector3(-CGFloat.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
    node.enumerateHierarchy { child, _ in
      guard let geometry = child.geometry else { return }
      let (a, b) = geometry.boundingBox
      for corner in [SCNVector3(a.x, a.y, a.z), SCNVector3(a.x, a.y, b.z), SCNVector3(a.x, b.y, a.z), SCNVector3(a.x, b.y, b.z),
                     SCNVector3(b.x, a.y, a.z), SCNVector3(b.x, a.y, b.z), SCNVector3(b.x, b.y, a.z), SCNVector3(b.x, b.y, b.z)] {
        let p = node.convertPosition(corner, from: child)
        low = SCNVector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = SCNVector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
      }
    }
    return (low, high)
  }
}
