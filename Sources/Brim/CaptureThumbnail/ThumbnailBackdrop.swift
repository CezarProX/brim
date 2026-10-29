import AppKit

/// A soft colour wash of a capture for the card behind it: the image shrunk to a few pixels, which
/// a smooth upscale turns into gentle gradients. A bitmap rather than a live blur filter, so it is
/// cheap and looks the same on screen and in renders.
enum ThumbnailBackdrop {
  static let pixelSize = CGSize(width: 12, height: 9)

  static func wash(for image: NSImage) -> NSImage? {
    guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(
        data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .medium
    context.draw(source, in: CGRect(origin: .zero, size: pixelSize))
    guard let small = context.makeImage() else { return nil }
    return NSImage(cgImage: small, size: pixelSize)
  }
}
