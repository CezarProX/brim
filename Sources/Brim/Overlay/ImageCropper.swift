// ImageCropper.swift
// Brim
//
// Crops a frozen full-screen screenshot down to a selection rectangle, for
// hand-off to `EditorSession.render(over:canvasSize:)`. This is a local,
// in-module implementation of the crop step — the overlay never calls into
// `ScreenCapturer`.

import AppKit

enum ImageCropper {

    /// - Parameters:
    ///   - frozenImage: An `NSImage` whose point size equals the screen's
    ///     point frame (per the `ScreenCapturer` contract), backed by pixel
    ///     data at whatever resolution the capture produced.
    ///   - rect: The selection, in the same points-based, bottom-left
    ///     origin, y-up coordinate space as the overlay view geometry (i.e.
    ///     the screen's/window's local coordinates).
    ///
    /// The points->pixels ratio is derived from the image itself
    /// (`cgImage.width / frozenImage.size.width`) rather than the screen's
    /// `backingScaleFactor`: on scaled Retina modes the captured native
    /// pixel size is NOT points x backingScaleFactor, and using the wrong
    /// ratio crops a shifted, zoomed region.
    static func crop(_ frozenImage: NSImage, toPointsRect rect: CGRect) -> NSImage? {
        guard rect.width > 0, rect.height > 0,
              frozenImage.size.width > 0, frozenImage.size.height > 0 else { return nil }
        guard let cgImage = frozenImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / frozenImage.size.width
        let scaleY = CGFloat(cgImage.height) / frozenImage.size.height

        // `cgImage` uses a top-left-origin, y-down pixel space; `rect` is in
        // points with a bottom-left origin, y-up (AppKit convention), so the
        // vertical axis needs flipping before scaling up to pixels.
        let flippedOriginY = frozenImage.size.height - rect.origin.y - rect.height
        let pixelRect = CGRect(
            x: (rect.origin.x * scaleX).rounded(),
            y: (flippedOriginY * scaleY).rounded(),
            width: (rect.width * scaleX).rounded(),
            height: (rect.height * scaleY).rounded()
        )

        // Clamp to the image's actual pixel bounds defensively: rounding, or
        // a selection dragged a hair past the screen edge, could otherwise
        // push the crop rect just outside the source image.
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clamped = pixelRect.intersection(imageBounds)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return nil }

        guard let cropped = cgImage.cropping(to: clamped) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}
