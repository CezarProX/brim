import SceneKit

/// Proportions of one earbud, in stem lengths of the Pro. Directions are for the left bud, whose
/// inner side (towards the other bud) is +x and whose front faces the camera (+z).
struct AirPodsBudSpec {
  var stemLength: CGFloat
  var stemBottomRadius: CGFloat
  var stemTopRadius: CGFloat
  /// Ellipsoid radii of the head.
  var headRadii: SCNVector3
  var headCenter: SCNVector3
  /// Roll of the head around the view axis; negative drops its inner side.
  var headRoll: CGFloat
  /// Silicone ear tip (Pro) instead of a hard speaker nozzle.
  var hasEarTip: Bool
  /// Where the tip or nozzle points, from the head center (normalized when used).
  var tipDirection: SCNVector3
  /// Dark vent on the outer face.
  var ventDirection: SCNVector3
  var ventSize: CGSize
  /// Half the distance between the two stems.
  var spacing: CGFloat

  static func spec(for kind: AirPodsDeviceKind) -> AirPodsBudSpec {
    switch kind {
    case .pro: pro
    case .gen3, .gen4: gen3
    case .original, .max: original
    }
  }

  static let pro = AirPodsBudSpec(
    stemLength: 1.0, stemBottomRadius: 0.145, stemTopRadius: 0.16,
    headRadii: SCNVector3(0.5, 0.45, 0.42), headCenter: SCNVector3(0.2, 1.38, -0.02), headRoll: -0.36,
    hasEarTip: true, tipDirection: SCNVector3(0.55, -0.38, 0.78),
    ventDirection: SCNVector3(-0.42, 0.4, 0.8), ventSize: CGSize(width: 0.27, height: 0.085), spacing: 0.98)

  static let gen3 = AirPodsBudSpec(
    stemLength: 0.86, stemBottomRadius: 0.15, stemTopRadius: 0.17,
    headRadii: SCNVector3(0.5, 0.46, 0.46), headCenter: SCNVector3(0.16, 1.28, 0), headRoll: -0.2,
    hasEarTip: false, tipDirection: SCNVector3(0.6, -0.15, 0.78),
    ventDirection: SCNVector3(-0.5, 0.35, 0.79), ventSize: CGSize(width: 0.2, height: 0.075), spacing: 0.95)

  static let original = AirPodsBudSpec(
    stemLength: 1.22, stemBottomRadius: 0.12, stemTopRadius: 0.13,
    headRadii: SCNVector3(0.42, 0.4, 0.4), headCenter: SCNVector3(0.12, 1.56, 0), headRoll: -0.15,
    hasEarTip: false, tipDirection: SCNVector3(0.62, -0.1, 0.78),
    ventDirection: SCNVector3(-0.55, 0.3, 0.78), ventSize: CGSize(width: 0.1, height: 0.05), spacing: 0.85)
}

/// Small vector helpers shared by the builders.
enum AirPods3DMath {
  static func normalized(_ v: SCNVector3) -> SCNVector3 {
    let length = max(1e-6, sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
    return SCNVector3(v.x / length, v.y / length, v.z / length)
  }

  /// Point on an axis-aligned ellipsoid surface in direction `direction` from its center.
  static func ellipsoidPoint(radii: SCNVector3, direction: SCNVector3) -> SCNVector3 {
    let d = normalized(direction)
    let scale = 1 / sqrt(pow(d.x / radii.x, 2) + pow(d.y / radii.y, 2) + pow(d.z / radii.z, 2))
    return SCNVector3(d.x * scale, d.y * scale, d.z * scale)
  }

  /// Outward surface normal of an axis-aligned ellipsoid at `point`.
  static func ellipsoidNormal(radii: SCNVector3, at point: SCNVector3) -> SCNVector3 {
    normalized(SCNVector3(point.x / (radii.x * radii.x), point.y / (radii.y * radii.y), point.z / (radii.z * radii.z)))
  }

  /// Turns `node` so its local +Y axis points along `direction`.
  static func alignY(_ node: SCNNode, to direction: SCNVector3) {
    let d = normalized(direction)
    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
  }

  static func mirrored(_ v: SCNVector3, side: CGFloat) -> SCNVector3 { SCNVector3(v.x * side, v.y, v.z) }
}
