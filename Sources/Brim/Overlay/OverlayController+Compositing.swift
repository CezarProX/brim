// OverlayController+Compositing.swift
// Brim
//
// Turns the current selection into a final image and fires `onAction`.

import AppKit

extension OverlayController {

    func performAction(_ action: OverlayAction) {
        guard let image = compositeFinalImage() else { return }
        onAction?(action, image)
    }

    /// Crops the active screen's frozen image to the selection (points ->
    /// pixels via the image's own pixel/point ratio), then flattens any
    /// annotations over it via the editing session. Cropping is done locally
    /// with `ImageCropper` — the overlay never calls into `ScreenCapturer`.
    private func compositeFinalImage() -> NSImage? {
        guard let screen = activeScreen, let rect = selectionRect,
              let frozen = frozenImages[screen] else {
            return nil
        }
        guard let cropped = ImageCropper.crop(frozen, toPointsRect: rect) else {
            return nil
        }
        guard let session else { return cropped }
        return session.render(over: cropped, canvasSize: rect.size)
    }
}
