import AppKit
import SceneKit

/// A stylised AirPods Max: knit canopy under a steel headband, telescoping arms, two rounded
/// aluminium cups with fabric cushions facing each other, and the Digital Crown.
enum AirPodsMaxBuilder {
  static let cupOffset: CGFloat = 0.8
  static let bandCenterY: CGFloat = 1.36

  static func make() -> SCNNode {
    let root = SCNNode()
    root.name = "max"
    root.addChildNode(arc(name: "max.frame", radius: 0.84, thickness: 0.05, depth: 0.07, material: AirPods3DMaterials.chrome()))
    root.addChildNode(arc(name: "max.canopy", radius: 0.74, thickness: 0.07, depth: 0.42,
                          material: AirPods3DMaterials.fabric(white: 0.82)))
    for side in [CGFloat(-1), 1] {
      root.addChildNode(arm(side: side))
      root.addChildNode(cup(side: side))
      root.addChildNode(cushion(side: side))
    }
    root.addChildNode(crown())
    return root
  }

  /// Upper half-ring band in the XY plane, extruded along z.
  private static func arc(name: String, radius: CGFloat, thickness: CGFloat, depth: CGFloat, material: SCNMaterial) -> SCNNode {
    let path = NSBezierPath()
    path.appendArc(withCenter: .zero, radius: radius + thickness / 2, startAngle: 0, endAngle: 180)
    path.appendArc(withCenter: .zero, radius: radius - thickness / 2, startAngle: 180, endAngle: 0, clockwise: true)
    path.close()
    path.flatness = 0.004
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.chamferRadius = min(thickness, depth) * 0.4
    shape.firstMaterial = material
    let node = SCNNode(geometry: shape)
    node.name = name
    node.position = SCNVector3(0, bandCenterY, 0)
    return node
  }

  private static func arm(side: CGFloat) -> SCNNode {
    let rod = SCNCylinder(radius: 0.028, height: 0.4)
    rod.radialSegmentCount = 16
    rod.firstMaterial = AirPods3DMaterials.chrome()
    let node = SCNNode(geometry: rod)
    node.name = side < 0 ? "max.arm.left" : "max.arm.right"
    node.position = SCNVector3(side * 0.84, bandCenterY - 0.2, 0)
    return node
  }

  private static func cup(side: CGFloat) -> SCNNode {
    let box = SCNBox(width: 0.34, height: 0.98, length: 0.8, chamferRadius: 0.14)
    box.chamferSegmentCount = 8
    box.firstMaterial = AirPods3DMaterials.aluminium()
    let node = SCNNode(geometry: box)
    node.name = side < 0 ? "max.cup.left" : "max.cup.right"
    node.position = SCNVector3(side * (cupOffset + 0.08), 0.6, 0)
    return node
  }

  private static func cushion(side: CGFloat) -> SCNNode {
    let box = SCNBox(width: 0.22, height: 0.86, length: 0.7, chamferRadius: 0.1)
    box.chamferSegmentCount = 6
    box.firstMaterial = AirPods3DMaterials.fabric(white: 0.3)
    let node = SCNNode(geometry: box)
    node.name = side < 0 ? "max.cushion.left" : "max.cushion.right"
    node.position = SCNVector3(side * (cupOffset - 0.18), 0.6, 0)
    return node
  }

  private static func crown() -> SCNNode {
    let knob = SCNCylinder(radius: 0.06, height: 0.07)
    knob.radialSegmentCount = 20
    knob.firstMaterial = AirPods3DMaterials.chrome()
    let node = SCNNode(geometry: knob)
    node.name = "max.crown"
    node.position = SCNVector3(cupOffset + 0.12, 1.1, -0.2)
    return node
  }
}
