import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image operations built on ImageIO and CoreGraphics. All functions are synchronous
/// and meant to be called off the main actor.
enum ImageTransforms {
  // MARK: Decoding & encoding

  static func fileExtension(for type: UTType) -> String {
    switch type {
    case .jpeg: "jpg"
    case .tiff: "tiff"
    default: type.preferredFilenameExtension ?? "img"
    }
  }

  static func sourceType(_ url: URL) -> UTType? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let id = CGImageSourceGetType(source) as String?
    else { return nil }
    return UTType(id)
  }

  /// The image with its EXIF orientation applied, optionally limited to `maxPixel` on its longest side.
  static func decode(_ url: URL, maxPixel: Int? = nil) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw TransformError.unreadable(url.lastPathComponent)
    }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
    let height = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
    let limit = min(maxPixel ?? .max, max(width, height, 1))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, limit),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw TransformError.unreadable(url.lastPathComponent)
    }
    return image
  }

  /// Exif / GPS / TIFF / IPTC dictionaries worth carrying to a re-encoded copy.
  /// Orientation is dropped because the pixels are already upright.
  static func carriedMetadata(of url: URL) -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return [:] }
    var carried: [CFString: Any] = [:]
    for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
      if let value = props[key] { carried[key] = value }
    }
    if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = nil
      carried[kCGImagePropertyTIFFDictionary] = tiff
    }
    return carried
  }

  static func encode(
    _ image: CGImage, as type: UTType, quality: Double, metadata: [CFString: Any] = [:]
  ) throws -> Data {
    if type == .webP, !ExternalCodecs.nativeWebP, OptionalTools.isAvailable(.cwebp) {
      return try ExternalCodecs.encodeWebP(image, quality: quality)
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
      throw TransformError.unsupported(type.localizedDescription ?? type.identifier)
    }
    var properties = metadata
    properties[kCGImageDestinationLossyCompressionQuality] = quality
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw TransformError.failed("Couldn’t encode the image.")
    }
    return data as Data
  }

  static func write(_ data: Data, to url: URL) throws {
    do { try data.write(to: url, options: .atomic) } catch {
      throw TransformError.failed("Couldn’t save \(url.lastPathComponent).")
    }
  }

  // MARK: Pixels

  /// True only when some pixel is actually see-through (screenshots carry an unused alpha channel).
  static func hasTransparency(_ image: CGImage) -> Bool {
    let side = 48
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(
        data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard drawn else { return false }
    return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
  }

  static func redrawn(_ image: CGImage, width: Int, height: Int, flattenOnWhite: Bool = false, rotate degrees: Int = 0) -> CGImage? {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    if flattenOnWhite {
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    if degrees == 0 {
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    } else {
      // Clockwise in a y-up context is a negative angle; the drawn rect is the unrotated size.
      let drawWidth = degrees % 180 == 0 ? width : height
      let drawHeight = degrees % 180 == 0 ? height : width
      context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
      context.rotate(by: -CGFloat(degrees) * .pi / 180)
      context.draw(image, in: CGRect(x: -CGFloat(drawWidth) / 2, y: -CGFloat(drawHeight) / 2,
                                     width: CGFloat(drawWidth), height: CGFloat(drawHeight)))
    }
    return context.makeImage()
  }

  static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
    guard factor < 0.999 else { return image }
    return redrawn(image, width: max(1, Int(Double(image.width) * factor)),
                   height: max(1, Int(Double(image.height) * factor)))
  }

  // MARK: Format choice

  static func outputType(for requested: TransformImageFormat, source: UTType?, transparent: Bool) -> UTType {
    if let type = requested.type, TransformImageFormat.writable([requested]).contains(requested) { return type }
    if let source, source.conforms(to: .heic) { return .heic }
    if transparent { return .png }
    return .jpeg
  }

  // MARK: Operations

  static func compress(_ source: URL, options: TransformOptions, context: TransformContext) throws -> URL {
    var image = try decode(source, maxPixel: options.limitLongestSide ? options.maxDimension : nil)
    let type = outputType(
      for: options.imageFormat, source: sourceType(source), transparent: hasTransparency(image))
    if type == .jpeg, hasTransparency(image),
      let flat = redrawn(image, width: image.width, height: image.height, flattenOnWhite: true)
    { image = flat }
    let metadata = options.stripMetadata ? [:] : carriedMetadata(of: source)
    let data: Data
    if let target = options.targetBytes {
      data = try fitToBudget(image, type: type, target: Int(target), metadata: metadata)
    } else {
      data = try encode(image, as: type, quality: options.imageQuality, metadata: metadata)
    }
    try context.checkCancelled()
    let output = context.output(for: source, suffix: "compressed", fileExtension: fileExtension(for: type))
    try write(data, to: output)
    return output
  }

  /// Encodes at the best quality/resolution that still fits, using `TransformSearch`.
  static func fitToBudget(_ image: CGImage, type: UTType, target: Int, metadata: [CFString: Any]) throws -> Data {
    var cache: [Double: CGImage] = [:]
    var encoded: [String: Data] = [:]
    let attempt = try TransformSearch.fit(target: target) { quality, scale in
      if cache[scale] == nil { cache[scale] = scaled(image, by: scale) }
      guard let scaledImage = cache[scale] else { throw TransformError.failed("Couldn’t resize the image.") }
      let data = try encode(scaledImage, as: type, quality: quality, metadata: metadata)
      encoded["\(quality)-\(scale)"] = data
      return data.count
    }
    guard let data = encoded["\(attempt.quality)-\(attempt.scale)"] else {
      throw TransformError.failed("Couldn’t compress the image.")
    }
    return data
  }

  static func targetSize(width: Int, height: Int, options: TransformOptions) -> (Int, Int) {
    let longest = max(width, height)
    let factor: Double
    switch options.resizeMode {
    case .maxDimension: factor = min(1, Double(max(1, options.maxDimension)) / Double(longest))
    case .percent: factor = min(1, Double(max(1, options.percent)) / 100)
    }
    return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
  }

  static func resize(_ source: URL, options: TransformOptions, context: TransformContext) throws -> URL {
    let image = try decode(source)
    let (width, height) = targetSize(width: image.width, height: image.height, options: options)
    guard let resized = redrawn(image, width: width, height: height) else {
      throw TransformError.failed("Couldn’t resize \(source.lastPathComponent).")
    }
    var type = sourceType(source) ?? .png
    if !TransformImageFormat.writable().compactMap(\.type).contains(type) { type = .png }
    let metadata = options.stripMetadata ? [:] : carriedMetadata(of: source)
    let data = try encode(resized, as: type, quality: 0.92, metadata: metadata)
    let output = context.output(for: source, suffix: "\(width)x\(height)", fileExtension: fileExtension(for: type))
    try write(data, to: output)
    return output
  }

  static func convert(_ source: URL, options: TransformOptions, context: TransformContext) throws -> URL {
    var image = try decode(source)
    let type = options.convertFormat.type ?? .jpeg
    if type == .jpeg,
      let flat = redrawn(image, width: image.width, height: image.height, flattenOnWhite: true)
    { image = flat }
    let data = try encode(image, as: type, quality: 0.9, metadata: carriedMetadata(of: source))
    let output = context.output(for: source, suffix: "", fileExtension: fileExtension(for: type))
    try write(data, to: output)
    return output
  }

  static func rotate(_ source: URL, options: TransformOptions, context: TransformContext) throws -> URL {
    let image = try decode(source)
    let degrees = options.clampedRotation
    let swap = degrees % 180 != 0
    guard let rotated = redrawn(
      image, width: swap ? image.height : image.width, height: swap ? image.width : image.height,
      rotate: degrees)
    else { throw TransformError.failed("Couldn’t rotate \(source.lastPathComponent).") }
    let type = sourceType(source) ?? .png
    let data = try encode(rotated, as: type, quality: 0.92, metadata: options.stripMetadata ? [:] : carriedMetadata(of: source))
    let output = context.output(for: source, suffix: "rotated", fileExtension: fileExtension(for: type))
    try write(data, to: output)
    return output
  }

  /// Removes EXIF, GPS, IPTC and XMP without touching the pixels when ImageIO can copy
  /// losslessly, and by re-encoding otherwise.
  static func stripMetadata(_ source: URL, context: TransformContext) throws -> URL {
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let typeID = CGImageSourceGetType(input)
    else { throw TransformError.unreadable(source.lastPathComponent) }
    let type = UTType(typeID as String) ?? .jpeg
    let output = context.output(for: source, suffix: "clean", fileExtension: fileExtension(for: type))
    if copyWithoutMetadata(input, typeID: typeID, to: output) { return output }
    try? FileManager.default.removeItem(at: output)
    let image = try decode(source)
    try write(try encode(image, as: type, quality: 0.95), to: output)
    return output
  }

  private static func copyWithoutMetadata(_ input: CGImageSource, typeID: CFString, to output: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, typeID, 1, nil) else { return false }
    let options: [CFString: Any] = [
      kCGImageMetadataShouldExcludeGPS: true,
      kCGImageMetadataShouldExcludeXMP: true,
      kCGImageDestinationMergeMetadata: false,
      kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
      kCGImagePropertyExifDictionary: kCFNull as Any,
      kCGImagePropertyGPSDictionary: kCFNull as Any,
      kCGImagePropertyIPTCDictionary: kCFNull as Any,
    ]
    var error: Unmanaged<CFError>?
    return CGImageDestinationCopyImageSource(destination, input, options as CFDictionary, &error)
  }
}
