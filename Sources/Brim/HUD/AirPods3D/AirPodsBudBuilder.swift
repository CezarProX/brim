import SceneKit

/// Builds one earbud from simple parts: a lathed stem with a chrome foot, an ellipsoid head, a
/// silicone tip or hard nozzle, a dark vent and a sensor window. `side` is +1 for the left bud
/// (inner side +x) and -1 for its mirror image.
enum AirPodsBudBuilder {
  static let radialSegments = 32

  static func makeBud(_ spec: AirPodsBudSpec, side: CGFloat) -> SCNNode {
    let bud = SCNNode()
    bud.name = side > 0 ? "bud.left" : "bud.right"
    bud.addChildNode(stem(spec))
    bud.addChildNode(foot(spec))
    bud.addChildNode(head(spec, side: side))
    return bud
  }

  private static func stem(_ spec: AirPodsBudSpec) -> SCNNode {
    let (bottom, top, length) = (spec.stemBottomRadius, spec.stemTopRadius, spec.stemLength)
    let profile = [
      CGPoint(x: 0, y: 0.04), CGPoint(x: bottom * 0.8, y: 0.04), CGPoint(x: bottom * 0.97, y: 0.05),
      CGPoint(x: bottom, y: 0.07), CGPoint(x: (bottom + top) / 2, y: length * 0.55),
      CGPoint(x: top, y: length), CGPoint(x: top * 0.9, y: length + 0.08), CGPoint(x: 0, y: length + 0.1),
    ]
    let node = SCNNode(geometry: LatheGeometry.make(profile: profile, segments: radialSegments))
    node.geometry?.firstMaterial = AirPods3DMaterials.gloss()
    node.name = "stem"
    node.scale = SCNVector3(1, 1, 0.86)
    return node
  }

  /// Chrome cap at the bottom of the stem.
  private static func foot(_ spec: AirPodsBudSpec) -> SCNNode {
    let r = spec.stemBottomRadius
    let profile = [
      CGPoint(x: 0, y: 0), CGPoint(x: r * 0.85, y: 0), CGPoint(x: r * 0.99, y: 0.012),
      CGPoint(x: r * 1.01, y: 0.03), CGPoint(x: r * 1.0, y: 0.06), CGPoint(x: 0, y: 0.06),
    ]
    let node = SCNNode(geometry: LatheGeometry.make(profile: profile, segments: radialSegments))
    node.geometry?.firstMaterial = AirPods3DMaterials.chrome()
    node.name = "foot"
    node.scale = SCNVector3(1, 1, 0.86)
    return node
  }

  private static func head(_ spec: AirPodsBudSpec, side: CGFloat) -> SCNNode {
    let pivot = SCNNode()
    pivot.name = "head"
    pivot.position = AirPods3DMath.mirrored(spec.headCenter, side: side)
    pivot.eulerAngles.z = spec.headRoll * side
    let sphere = SCNSphere(radius: 1)
    sphere.segmentCount = 40
    sphere.firstMaterial = AirPods3DMaterials.gloss()
    let shell = SCNNode(geometry: sphere)
    shell.name = "shell"
    shell.scale = spec.headRadii
    pivot.addChildNode(shell)
    let tip = AirPods3DMath.mirrored(spec.tipDirection, side: side)
    pivot.addChildNode(spec.hasEarTip ? earTip(spec, direction: tip) : nozzle(spec, direction: tip))
    pivot.addChildNode(vent(spec, direction: AirPods3DMath.mirrored(spec.ventDirection, side: side)))
    pivot.addChildNode(sensor(spec, side: side))
    return pivot
  }

  /// Silicone tip: a short neck flaring into a rounded dome, with a recessed dark opening.
  static let earTipProfile: [CGPoint] = [
    CGPoint(x: 0, y: 0), CGPoint(x: 0.15, y: 0), CGPoint(x: 0.15, y: 0.05), CGPoint(x: 0.18, y: 0.085),
    CGPoint(x: 0.245, y: 0.125), CGPoint(x: 0.285, y: 0.175), CGPoint(x: 0.295, y: 0.22), CGPoint(x: 0.28, y: 0.265),
    CGPoint(x: 0.235, y: 0.305), CGPoint(x: 0.165, y: 0.33), CGPoint(x: 0.095, y: 0.338), CGPoint(x: 0.07, y: 0.33),
    CGPoint(x: 0.062, y: 0.31), CGPoint(x: 0, y: 0.305),
  ]

  private static func earTip(_ spec: AirPodsBudSpec, direction: SCNVector3) -> SCNNode {
    let node = SCNNode(geometry: LatheGeometry.make(profile: earTipProfile, segments: radialSegments))
    node.geometry?.firstMaterial = AirPods3DMaterials.silicone()
    node.name = "tip"
    node.scale = SCNVector3(1.12, 1.05, 1.12)
    node.position = scaled(AirPods3DMath.ellipsoidPoint(radii: spec.headRadii, direction: direction), 0.8)
    AirPods3DMath.alignY(node, to: direction)
    node.addChildNode(opening(radius: 0.064, at: 0.308))
    return node
  }

  /// Hard speaker nozzle of the open-fit buds, with a dark mesh at its end.
  private static func nozzle(_ spec: AirPodsBudSpec, direction: SCNVector3) -> SCNNode {
    let radius = spec.headRadii.y * 0.42
    let profile = LatheGeometry.profile(samples: 12, radius: { t in radius * sqrt(max(0, 1 - pow(t, 6))) },
                                        height: { t in 0.15 * t })
    let node = SCNNode(geometry: LatheGeometry.make(profile: profile, segments: radialSegments))
    node.geometry?.firstMaterial = AirPods3DMaterials.gloss()
    node.name = "nozzle"
    node.position = scaled(AirPods3DMath.ellipsoidPoint(radii: spec.headRadii, direction: direction), 0.9)
    AirPods3DMath.alignY(node, to: direction)
    node.addChildNode(opening(radius: radius * 0.44, at: 0.148, material: AirPods3DMaterials.mesh()))
    return node
  }

  private static func opening(radius: CGFloat, at height: CGFloat,
                              material: SCNMaterial = AirPods3DMaterials.grill()) -> SCNNode {
    let disc = SCNCylinder(radius: radius, height: 0.006)
    disc.radialSegmentCount = 24
    disc.firstMaterial = material
    let node = SCNNode(geometry: disc)
    node.name = "mesh"
    node.position = SCNVector3(0, height, 0)
    return node
  }

  /// Dark pill-shaped vent lying flat on the head.
  private static func vent(_ spec: AirPodsBudSpec, direction: SCNVector3) -> SCNNode {
    let size = spec.ventSize
    let pill = SCNCapsule(capRadius: size.height / 2, height: size.width)
    pill.radialSegmentCount = 16
    pill.firstMaterial = AirPods3DMaterials.grill()
    let inner = SCNNode(geometry: pill)
    inner.scale = SCNVector3(1, 1, 0.25)
    inner.eulerAngles.z = .pi / 2 + 0.3 * (direction.x < 0 ? -1 : 1)
    return surfaceMount(inner, name: "vent", spec: spec, direction: direction, sink: 0.985)
  }

  /// Small optical sensor on the inner, upper face.
  private static func sensor(_ spec: AirPodsBudSpec, side: CGFloat) -> SCNNode {
    let dot = SCNCylinder(radius: 0.045, height: 0.01)
    dot.radialSegmentCount = 16
    dot.firstMaterial = AirPods3DMaterials.sensor()
    let inner = SCNNode(geometry: dot)
    inner.eulerAngles.x = .pi / 2
    return surfaceMount(inner, name: "sensor", spec: spec, direction: SCNVector3(0.3 * side, 0.5, -0.8), sink: 0.995)
  }

  /// Places `inner` (built facing +z) on the head surface, facing out along the surface normal.
  private static func surfaceMount(_ inner: SCNNode, name: String, spec: AirPodsBudSpec,
                                   direction: SCNVector3, sink: CGFloat) -> SCNNode {
    let point = AirPods3DMath.ellipsoidPoint(radii: spec.headRadii, direction: direction)
    let normal = AirPods3DMath.ellipsoidNormal(radii: spec.headRadii, at: point)
    let mount = SCNNode()
    mount.name = name
    mount.position = scaled(point, sink)
    mount.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1),
                                       to: SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z)))
    mount.addChildNode(inner)
    return mount
  }

  private static func scaled(_ v: SCNVector3, _ factor: CGFloat) -> SCNVector3 {
    SCNVector3(v.x * factor, v.y * factor, v.z * factor)
  }
}
