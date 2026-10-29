// ImageEncoder.swift
// Brim
//
// Small, focused helpers for turning an `NSImage` into PNG/JPEG `Data`,
// flattening transparency onto white when required, and reporting pixel
// dimensions for history records and file names.

import AppKit

enum ImageEncoder {

    enum Format: String {
        case png
        case jpg

        var fileExtension: String { rawValue }

        var contentType: String {
            switch self {
            case .png: return "image/png"
            case .jpg: return "image/jpeg"
            }
        }
    }

    enum EncodingError: Error, LocalizedError {
        case noBitmapSource
        case representationFailed

        var errorDescription: String? {
            switch self {
            case .noBitmapSource:
                return "Couldn't read the screenshot's pixel data."
            case .representationFailed:
                return "Couldn't encode the screenshot to the requested format."
            }
        }
    }

    /// The image's native pixel dimensions (not points).
    static func pixelSize(of image: NSImage) -> CGSize {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// A human-readable "WxH" string for the image's pixel dimensions.
    static func pixelSizeString(of image: NSImage) -> String {
        let size = pixelSize(of: image)
        return "\(Int(size.width))x\(Int(size.height))"
    }

    /// Encodes `image` as PNG or JPEG data, honoring transparency /
    /// quality settings.
    ///
    /// - Parameters:
    ///   - format: PNG or JPG.
    ///   - preserveTransparency: if `false` (or `format == .jpg`, which has
    ///     no alpha channel), the image is flattened onto a white background
    ///     before encoding.
    ///   - jpgQuality: compression quality for JPEG, `0...1`.
    static func data(
        from image: NSImage,
        format: Format,
        preserveTransparency: Bool,
        jpgQuality: Double
    ) throws -> Data {
        let shouldFlatten = !preserveTransparency || format == .jpg
        let sourceImage = shouldFlatten ? try flattenOntoWhite(image) : image

        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw EncodingError.noBitmapSource
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        switch format {
        case .png:
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw EncodingError.representationFailed
            }
            return data
        case .jpg:
            let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: jpgQuality
            ]
            guard let data = bitmap.representation(using: .jpeg, properties: properties) else {
                throw EncodingError.representationFailed
            }
            return data
        }
    }

    /// Always encodes `image` as PNG, preserving transparency exactly as-is
    /// (used for the clipboard, which supports alpha regardless of the
    /// user's save-format preference).
    static func pngDataPreservingAlpha(from image: NSImage) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw EncodingError.noBitmapSource
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw EncodingError.representationFailed
        }
        return data
    }

    /// Draws `image` onto an opaque white background at its native pixel
    /// resolution, discarding any alpha channel.
    static func flattenOntoWhite(_ image: NSImage) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw EncodingError.noBitmapSource
        }

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw EncodingError.representationFailed
        }

        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let flattened = context.makeImage() else {
            throw EncodingError.representationFailed
        }

        return NSImage(cgImage: flattened, size: image.size)
    }
}
