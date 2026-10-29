import AppKit
import SceneKit

/// A procedural photo-studio environment: a dark room with a large softbox overhead, two strip
/// lights at the sides and a faint floor bounce. Used as image-based lighting so the white
/// plastic gets soft, believable reflections without bundling an HDR file.
enum AirPods3DStudio {
  static let size = CGSize(width: 512, height: 256)

  /// Equirectangular image: x is longitude (0...360°), y is latitude (top = straight up).
  static func environmentImage() -> CGImage? {
    let (width, height) = (Int(size.width), Int(size.height))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    drawRoom(context, width: CGFloat(width), height: CGFloat(height))
    // Overhead softbox spans every longitude near the zenith (CG origin is bottom-left).
    softbox(context, CGRect(x: 0, y: CGFloat(height) * 0.8, width: CGFloat(width), height: CGFloat(height) * 0.2), white: 1)
    // Key strip in front-left, fill strip front-right, rim strip behind.
    softbox(context, CGRect(x: CGFloat(width) * 0.58, y: CGFloat(height) * 0.35, width: 46, height: 110), white: 0.95)
    softbox(context, CGRect(x: CGFloat(width) * 0.88, y: CGFloat(height) * 0.38, width: 34, height: 90), white: 0.6)
    softbox(context, CGRect(x: CGFloat(width) * 0.2, y: CGFloat(height) * 0.4, width: 40, height: 100), white: 0.8)
    return context.makeImage()
  }

  private static func drawRoom(_ context: CGContext, width: CGFloat, height: CGFloat) {
    let colors = [NSColor(white: 0.03, alpha: 1).cgColor, NSColor(white: 0.16, alpha: 1).cgColor,
                  NSColor(white: 0.32, alpha: 1).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) else { return }
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
  }

  /// A bright panel with a soft falloff around it.
  private static func softbox(_ context: CGContext, _ rect: CGRect, white: CGFloat) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: 18, color: NSColor(white: white, alpha: 1).cgColor)
    context.setFillColor(NSColor(white: white, alpha: 1).cgColor)
    context.fill(rect)
    context.restoreGState()
  }

  /// Key light from the upper left front, a cool rim from behind, and the studio environment.
  static func light(_ scene: SCNScene) {
    scene.lightingEnvironment.contents = environmentImage()
    scene.lightingEnvironment.intensity = 1.15
    scene.rootNode.addChildNode(directional(name: "light.key", intensity: 650, euler: SCNVector3(-0.6, -0.5, 0)))
    scene.rootNode.addChildNode(directional(name: "light.rim", intensity: 500, euler: SCNVector3(-0.3, 2.6, 0)))
  }

  private static func directional(name: String, intensity: CGFloat, euler: SCNVector3) -> SCNNode {
    let light = SCNLight()
    light.type = .directional
    light.intensity = intensity
    light.color = NSColor.white
    let node = SCNNode()
    node.name = name
    node.light = light
    node.eulerAngles = euler
    return node
  }
}
