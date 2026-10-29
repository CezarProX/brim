import AppKit
import SceneKit

/// Physically based materials for the procedural AirPods. Each call returns a fresh material so
/// scenes never share mutable state.
enum AirPods3DMaterials {
  static func gloss(white: CGFloat = 0.9, roughness: CGFloat = 0.26) -> SCNMaterial {
    let material = base(NSColor(white: white, alpha: 1), roughness: roughness, metalness: 0)
    material.clearCoat.contents = 0.75
    material.clearCoatRoughness.contents = 0.06
    return material
  }

  /// Silicone ear tip: slightly translucent, satin.
  static func silicone() -> SCNMaterial {
    let material = base(NSColor(white: 0.86, alpha: 1), roughness: 0.5, metalness: 0)
    material.transparency = 0.94
    return material
  }

  /// Dark acoustic mesh and sensor windows.
  static func grill() -> SCNMaterial { base(NSColor(white: 0.06, alpha: 1), roughness: 0.5, metalness: 0) }

  /// Grey speaker mesh on the open-fit buds, lighter than the vents.
  static func mesh() -> SCNMaterial { base(NSColor(white: 0.32, alpha: 1), roughness: 0.75, metalness: 0.1) }

  static func sensor() -> SCNMaterial { base(NSColor(white: 0.02, alpha: 1), roughness: 0.15, metalness: 0) }

  static func chrome() -> SCNMaterial { base(NSColor(white: 0.92, alpha: 1), roughness: 0.15, metalness: 1) }

  /// Anodized aluminium for the Max ear cups.
  static func aluminium() -> SCNMaterial { base(NSColor(white: 0.86, alpha: 1), roughness: 0.38, metalness: 0.85) }

  /// Knit canopy and cushion fabric.
  static func fabric(white: CGFloat) -> SCNMaterial { base(NSColor(white: white, alpha: 1), roughness: 0.95, metalness: 0) }

  private static func base(_ color: NSColor, roughness: CGFloat, metalness: CGFloat) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = color
    material.roughness.contents = roughness
    material.metalness.contents = metalness
    return material
  }
}
