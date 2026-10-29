// StudioFrameRenderer.swift
// Brim
//
// Draws one edited frame: background, shadowed rounded frame, the recording through the zoom
// camera (with hidden areas blurred), then the smoothed pointer and click ripples. The same
// renderer feeds the editor's still preview, the live AVPlayer preview (through the custom
// compositor) and the exporter, so what you see is what you export.

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

struct StudioRenderInputs: Sendable {
    var edit: StudioEdit
    var metadata: RecordingMetadata
    var track: CursorTrack
}

final class StudioFrameRenderer: @unchecked Sendable {
    static let context = CIContext(options: [.workingColorSpace: StudioOverlayArt.sRGB, .cacheIntermediates: false])

    let inputs: StudioRenderInputs
    private let path: SmoothedCursorPath
    private let visibility: CursorVisibility
    private let camera: ZoomCameraPath
    private let lock = NSLock()
    private var cache: [String: CIImage] = [:]
    private var pointers: [Int: StudioOverlayArt.Pointer] = [:]

    /// `previous` lends its precomputed pointer and camera paths when only the look changed,
    /// so slider drags don't redo the smoothing and spring simulation.
    init(inputs: StudioRenderInputs, reusing previous: StudioFrameRenderer? = nil) {
        self.inputs = inputs
        let edit = inputs.edit
        if let previous, previous.inputs.track == inputs.track, previous.inputs.metadata == inputs.metadata,
           previous.inputs.edit.zooms == edit.zooms, previous.inputs.edit.crop == edit.crop,
           previous.inputs.edit.style.cursor.smoothing == edit.style.cursor.smoothing {
            path = previous.path
            visibility = previous.visibility
            camera = previous.camera
            return
        }
        path = SmoothedCursorPath(track: inputs.track, smoothing: edit.style.cursor.smoothing)
        visibility = CursorVisibility(track: inputs.track)
        // The camera follows a much softer copy of the pointer so zooms glide instead of twitching.
        let cameraPath = SmoothedCursorPath(track: inputs.track, smoothing: 1)
        let crop = edit.crop
        camera = ZoomCameraPath(segments: Self.croppedZooms(edit.zooms, crop: crop), duration: inputs.metadata.duration) { t in
            cameraPath.position(at: t).map { ExportGeometry.cropped($0, crop: crop) }
        }
    }

    /// Fixed focus points are stored against the full recording; the camera works in crop space.
    private static func croppedZooms(_ zooms: [ZoomSegment], crop: CGRect) -> [ZoomSegment] {
        zooms.map { zoom in
            var copy = zoom
            if case .fixed(let x, let y) = zoom.focus {
                let p = ExportGeometry.cropped(CGPoint(x: x, y: y), crop: crop)
                copy.focus = .fixed(x: p.x, y: p.y)
            }
            return copy
        }
    }

    /// Size of the cropped recording in video pixels.
    var contentPixels: CGSize {
        let crop = inputs.edit.crop, size = inputs.metadata.pixelSize
        return CGSize(width: size.width * crop.width, height: size.height * crop.height)
    }

    func canvasSize(_ settings: ExportSettings) -> CGSize {
        ExportGeometry.canvasSize(content: contentPixels, resolution: settings.effectiveResolution, aspect: settings.aspect)
    }

    func layout(canvas: CGSize) -> FrameLayout {
        ExportGeometry.layout(canvas: canvas, content: contentPixels, style: inputs.edit.style)
    }

    func cameraState(at sourceTime: Double) -> CameraState { camera.state(at: sourceTime) }

    // MARK: Composition

    func compose(source: CIImage, sourceTime: Double, canvas: CGSize) -> CIImage {
        let edit = inputs.edit
        let layout = layout(canvas: canvas)
        let frame = CGRect(x: layout.videoRect.minX, y: canvas.height - layout.videoRect.maxY,
                           width: layout.videoRect.width, height: layout.videoRect.height)
        let camera = camera.state(at: sourceTime)

        var content = hidingAreas(in: source, at: sourceTime)
        let extent = content.extent
        let crop = edit.crop
        let cropRect = CGRect(x: extent.minX + crop.minX * extent.width, y: extent.minY + (1 - crop.maxY) * extent.height,
                              width: crop.width * extent.width, height: crop.height * extent.height)
        content = content.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        let visible = camera.visibleRect
        let sx = camera.scale * frame.width / max(1, cropRect.width)
        let sy = camera.scale * frame.height / max(1, cropRect.height)
        let tx = frame.minX - visible.minX * camera.scale * frame.width
        let ty = frame.minY - (1 - visible.maxY) * camera.scale * frame.height
        content = content.clampedToExtent()
            .transformed(by: CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty))
            .cropped(to: frame)

        let key = "\(Int(canvas.width))x\(Int(canvas.height))|\(frame.debugDescription)|\(layout.cornerRadius)|\(layout.shadowRadius)"
        if layout.cornerRadius > 0.5 {
            let mask = cached("mask|" + key) { StudioOverlayArt.mask(canvas: canvas, frame: frame, radius: layout.cornerRadius) }
            content = content.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
            ])
        }
        var output = content
        if let shadow = cachedOptional("shadow|" + key, { StudioOverlayArt.shadow(canvas: canvas, frame: frame, layout: layout) }) {
            output = output.composited(over: shadow)
        }
        let backgroundKey = "bg|\(Int(canvas.width))x\(Int(canvas.height))|\(edit.style.background)"
        if let background = cachedOptional(backgroundKey, {
            StudioBackdrop.renderer.image(for: edit.style.background, size: canvas).map { CIImage(cgImage: $0) }
        }) {
            output = output.composited(over: background)
        }
        output = drawPointer(over: output, at: sourceTime, layout: layout, camera: camera, canvas: canvas)
        return output.cropped(to: CGRect(origin: .zero, size: canvas))
    }

    private func hidingAreas(in source: CIImage, at t: Double) -> CIImage {
        let extent = source.extent
        var image = source
        for area in inputs.edit.hiddenAreas where area.isActive(at: t) {
            let region = CGRect(x: extent.minX + area.rect.minX * extent.width, y: extent.minY + (1 - area.rect.maxY) * extent.height,
                                width: area.rect.width * extent.width, height: area.rect.height * extent.height)
                .integral.intersection(extent)
            guard !region.isEmpty else { continue }
            let short = Double(min(extent.width, extent.height))
            let effect: CIImage
            switch area.kind {
            case .blur:
                effect = image.clampedToExtent().applyingGaussianBlur(sigma: max(10, short * 0.022))
            case .pixelate:
                effect = image.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(10, short * 0.03), kCIInputCenterKey: CIVector(x: region.minX, y: region.minY),
                ])
            }
            image = effect.cropped(to: region).composited(over: image)
        }
        return image
    }

    private func drawPointer(over image: CIImage, at t: Double, layout: FrameLayout, camera: CameraState, canvas: CGSize) -> CIImage {
        let style = inputs.edit.style.cursor
        guard style.isVisible, let raw = path.position(at: t) else { return image }
        let crop = inputs.edit.crop
        let contentPoints = CGSize(width: inputs.metadata.pointWidth * crop.width, height: inputs.metadata.pointHeight * crop.height)
        let pointScale = ExportGeometry.pointScale(layout: layout, contentPoints: contentPoints, camera: camera)
        var output = image
        let frame = layout.videoRect
        if style.clickRipple, let ring = StudioOverlayArt.ripple {
            for (click, progress) in ClickEffect.ripples(at: t, clicks: inputs.track.clicks) {
                let point = ExportGeometry.canvasPoint(ExportGeometry.cropped(CGPoint(x: click.x, y: click.y), crop: crop),
                                                       layout: layout, camera: camera)
                guard frame.contains(point) else { continue }
                let eased = 1 - pow(1 - progress, 3)
                let radius = 22 * pointScale * (0.25 + 0.75 * eased) * max(1, style.size / 1.5)
                let scale = radius * 2 / ring.extent.width
                let placed = ring.transformed(by: CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(CGAffineTransform(translationX: point.x - radius, y: canvas.height - point.y - radius)))
                output = StudioOverlayArt.faded(placed, (1 - progress) * 0.7).composited(over: output)
            }
        }
        let point = ExportGeometry.canvasPoint(ExportGeometry.cropped(raw, crop: crop), layout: layout, camera: camera)
        guard frame.insetBy(dx: -2, dy: -2).contains(point) else { return output }
        let opacity = style.hidesWhenIdle ? visibility.opacity(at: t) : 1
        guard opacity > 0.01 else { return output }
        let press = ClickEffect.pointerScale(at: t, clicks: inputs.track.clicks)
        let height = max(8, Int((22 * style.size * pointScale * press).rounded()))
        guard let pointer = pointer(height: height) else { return output }
        let placed = pointer.image.transformed(by: CGAffineTransform(
            translationX: point.x - pointer.hotspot.x, y: canvas.height - point.y - pointer.hotspot.y))
        return StudioOverlayArt.faded(placed, opacity).composited(over: output)
    }

    // MARK: Output

    /// Renders straight into a pixel buffer (compositor and exporter path).
    func render(source: CIImage, sourceTime: Double, into buffer: CVPixelBuffer) {
        let canvas = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let image = compose(source: source, sourceTime: sourceTime, canvas: canvas)
        Self.context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: canvas), colorSpace: StudioOverlayArt.sRGB)
    }

    /// Renders a still (editor preview while paused, render tests).
    func stillImage(source: CGImage, sourceTime: Double, canvas: CGSize) -> CGImage? {
        let image = compose(source: CIImage(cgImage: source), sourceTime: sourceTime, canvas: canvas)
        return Self.context.createCGImage(image, from: CGRect(origin: .zero, size: canvas), format: .RGBA8, colorSpace: StudioOverlayArt.sRGB)
    }

    // MARK: Caches

    private func pointer(height: Int) -> StudioOverlayArt.Pointer? {
        lock.lock(); defer { lock.unlock() }
        if let hit = pointers[height] { return hit }
        if pointers.count > 48 { pointers.removeAll() }
        let made = StudioOverlayArt.pointer(height: height)
        pointers[height] = made
        return made
    }

    private func cached(_ key: String, _ make: () -> CIImage) -> CIImage {
        cachedOptional(key, { make() }) ?? make()
    }

    private func cachedOptional(_ key: String, _ make: () -> CIImage?) -> CIImage? {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let made = make() else { return nil }
        lock.lock()
        if cache.count > 24 { cache.removeAll() }
        cache[key] = made
        lock.unlock()
        return made
    }
}
