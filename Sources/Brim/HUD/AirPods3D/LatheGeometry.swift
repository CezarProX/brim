import SceneKit

/// Builds a closed surface of revolution around the Y axis from a profile of (radius, y) points
/// listed bottom to top. Normals come from the profile's tangent, so curves shade smoothly.
enum LatheGeometry {
  static func make(profile: [CGPoint], segments: Int) -> SCNGeometry {
    let rings = profile.count
    guard rings >= 2, segments >= 3 else { return SCNGeometry() }
    let normals2D = profileNormals(profile)
    var positions: [SCNVector3] = []
    var normals: [SCNVector3] = []
    positions.reserveCapacity(rings * (segments + 1))
    for ring in 0..<rings {
      for step in 0...segments {
        let angle = CGFloat(step) / CGFloat(segments) * 2 * .pi
        let (cosA, sinA) = (cos(angle), sin(angle))
        let point = profile[ring], normal = normals2D[ring]
        positions.append(SCNVector3(point.x * cosA, point.y, point.x * sinA))
        normals.append(SCNVector3(normal.x * cosA, normal.y, normal.x * sinA))
      }
    }
    let element = SCNGeometryElement(indices: indices(rings: rings, segments: segments), primitiveType: .triangles)
    return SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                       elements: [element])
  }

  /// Outward 2D normals: the profile tangent turned clockwise, averaged at interior points.
  static func profileNormals(_ profile: [CGPoint]) -> [CGPoint] {
    profile.indices.map { index in
      let previous = profile[max(0, index - 1)], next = profile[min(profile.count - 1, index + 1)]
      let tangent = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
      let length = max(1e-6, hypot(tangent.x, tangent.y))
      return CGPoint(x: tangent.y / length, y: -tangent.x / length)
    }
  }

  static func indices(rings: Int, segments: Int) -> [UInt32] {
    var result: [UInt32] = []
    result.reserveCapacity((rings - 1) * segments * 6)
    let stride = UInt32(segments + 1)
    for ring in 0..<UInt32(rings - 1) {
      for step in 0..<UInt32(segments) {
        let a = ring * stride + step, b = a + stride
        result += [a, b, a + 1, a + 1, b, b + 1]
      }
    }
    return result
  }

  /// A profile sampled from `radius(t)` and `height(t)` for t in 0...1.
  static func profile(samples: Int, radius: (CGFloat) -> CGFloat, height: (CGFloat) -> CGFloat) -> [CGPoint] {
    (0...samples).map { index in
      let t = CGFloat(index) / CGFloat(samples)
      return CGPoint(x: max(0, radius(t)), y: height(t))
    }
  }
}
