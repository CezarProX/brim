import AVFoundation
import AppKit

/// Finds macOS's own AirPods banner animation for a device: the transparent 6-second loops that
/// BluetoothUIService shows when AirPods connect. They are read in place from the system at run
/// time and never copied into the app. File existence is injectable so the lookup can be tested.
struct AirPodsBannerClip {
  static let systemRoot = URL(fileURLWithPath: "/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources")

  var root: URL = Self.systemRoot
  var fileExists: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }

  /// Product IDs with no banner of their own that look like one that has one
  /// (USB-C and ANC revisions share their predecessor's shape).
  static let aliases: [Int: Int] = [
    0x2024: 0x2014,  // AirPods Pro 2 (USB-C) → AirPods Pro 2
    0x2028: 0x2027,  // AirPods Pro 3 revision → AirPods Pro 3
    0x201B: 0x2019,  // AirPods 4 with ANC → AirPods 4
    0x201F: 0x200A,  // AirPods Max (USB-C) → AirPods Max
  ]

  /// When only the model is known, the banner most people own for it.
  static let kindProductIDs: [AirPodsDeviceKind: [Int]] = [
    .original: [0x200F, 0x2002],
    .gen3: [0x2013],
    .gen4: [0x2019],
    .pro: [0x2014, 0x200E],
    .max: [0x200A],
  ]

  /// Banner product IDs to try, best first: the device's own, its look-alike, then its model's.
  static func productIDs(productID: Int?, kind: AirPodsDeviceKind?) -> [Int] {
    var ids: [Int] = []
    for id in [productID, productID.flatMap { aliases[$0] }].compactMap({ $0 }) + (kind.flatMap { kindProductIDs[$0] } ?? [])
    where !ids.contains(id) {
      ids.append(id)
    }
    return ids
  }

  /// Paths for one product ID in lookup order: colour variant, the default colour, the plain loop.
  func candidates(productID: Int, colour: Int?) -> [URL] {
    let folder = root.appendingPathComponent("Banner-PID-\(productID)-mov")
    let names = [colour.map { "Banner-PID-\(productID)-\($0)-Loop.mov" },
                 "Banner-PID-\(productID)-default-Loop.mov", "Banner-PID-\(productID)-Loop.mov"]
    return names.compactMap { $0 }.map { folder.appendingPathComponent($0) }
  }

  /// The charging-case loop for a product ID.
  func caseClip(productID: Int) -> URL? {
    let url = root.appendingPathComponent("Banner-PID-\(productID)-Case-mov/Banner-PID-\(productID)-Case-Loop.mov")
    return fileExists(url.path) ? url : nil
  }

  /// The first banner that exists for this device, or nil (the card then falls back).
  func url(productID: Int?, kind: AirPodsDeviceKind?, colour: Int? = nil) -> URL? {
    for id in Self.productIDs(productID: productID, kind: kind) {
      if let url = candidates(productID: id, colour: colour).first(where: { fileExists($0.path) }) { return url }
    }
    return nil
  }
}

/// Still frames from a banner clip, cached, for Reduce Motion, a hidden card and render tests.
@MainActor
enum AirPodsBannerStills {
  private static var cache: [String: NSImage] = [:]

  static func frame(_ url: URL, at time: TimeInterval = 0) -> NSImage? {
    let key = "\(url.path)@\(time)"
    if let image = cache[key] { return image }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true
    guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    else { return nil }
    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    if cache.count > 64 { cache.removeAll() }
    cache[key] = image
    return image
  }
}
