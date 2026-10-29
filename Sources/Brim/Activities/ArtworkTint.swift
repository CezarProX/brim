import AppKit
import CoreImage
import SwiftUI

/// Derives a lively accent from album art, the way the system tints its music waveform.
@MainActor
enum ArtworkTint {
  private static var cache: [ObjectIdentifier: Color] = [:]
  private static let context = CIContext(options: [.workingColorSpace: NSNull()])

  static func color(for image: NSImage?) -> Color? {
    guard let image else { return nil }
    let key = ObjectIdentifier(image)
    if let cached = cache[key] { return cached }
    guard let color = averageColor(of: image) else { return nil }
    if cache.count > 32 { cache.removeAll() }
    cache[key] = color
    return color
  }

  private static func averageColor(of image: NSImage) -> Color? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let input = CIImage(cgImage: cgImage)
    guard
      let filter = CIFilter(
        name: "CIAreaAverage",
        parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
      let output = filter.outputImage
    else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    context.render(
      output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8, colorSpace: nil)
    let average = NSColor(
      srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
      blue: CGFloat(pixel[2]) / 255, alpha: 1)
    // Average art is usually muddy; lift it so it reads on black.
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
    if saturation < 0.12 { return Color.white.opacity(0.85) }
    return Color(
      hue: hue, saturation: min(1, max(0.45, saturation * 1.2)), brightness: max(0.82, brightness))
  }
}
