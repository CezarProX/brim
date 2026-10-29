// ScreenCapturer.swift
// Brim
//
// Captures frozen full-screen images (one per display) and crops the final
// selection out of them. Backed by ScreenCaptureKit.

import AppKit
import ScreenCaptureKit

enum ScreenCapturer {

    /// Errors surfaced while capturing full-screen images.
    enum CaptureError: Error, LocalizedError {
        case permissionDenied
        case noDisplaysFound
        case screenNotMatched
        case captureFailed(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Brim doesn't have Screen Recording permission. Enable it in System Settings > Privacy & Security > Screen Recording."
            case .noDisplaysFound:
                return "No displays were found to capture."
            case .screenNotMatched:
                return "Couldn't match a display to an on-screen NSScreen."
            case .captureFailed(let underlying):
                if let underlying {
                    return "Screen capture failed: \(underlying.localizedDescription)"
                }
                return "Screen capture failed for an unknown reason."
            }
        }
    }

    /// Captures a frozen image of every connected display at full pixel
    /// resolution, wrapped as an `NSImage` sized in points so it renders 1:1
    /// on its originating screen.
    ///
    /// - Returns: a mapping from each `NSScreen` to the `NSImage` frozen for it.
    static func captureFullScreens() async throws -> [NSScreen: NSImage] {
        // Let ScreenCaptureKit determine access for the actual capture request.
        // A separate CoreGraphics preflight can reject before SCK has a chance
        // to refresh access or present its native permission request.
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            throw classifyCaptureError(error)
        }

        guard !shareableContent.displays.isEmpty else {
            throw CaptureError.noDisplaysFound
        }

        var result: [NSScreen: NSImage] = [:]

        for scDisplay in shareableContent.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == scDisplay.displayID }) else {
                // A display reported by ScreenCaptureKit that doesn't map to
                // an NSScreen (e.g. a mirrored/disabled display) — skip it
                // rather than failing the whole capture.
                continue
            }

            let image = try await captureImage(for: scDisplay, screen: screen)
            result[screen] = image
        }

        guard !result.isEmpty else {
            throw CaptureError.screenNotMatched
        }

        return result
    }

    static func classifyCaptureError(_ error: Error) -> CaptureError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .captureFailed(underlying: error)
    }

    /// Captures a single display via `SCScreenshotManager` at full native
    /// pixel resolution and wraps it as a point-sized `NSImage`.
    private static func captureImage(for scDisplay: SCDisplay, screen: NSScreen) async throws -> NSImage {
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        // NOTE: `CGDisplayPixelsWide`/`CGDisplayPixelsHigh` are misleadingly
        // named — on a scaled Retina display they return the current
        // *point* resolution (e.g. 1512x982), not the native pixel
        // resolution (e.g. 3024x1964). Using them here silently captured at
        // 1x and let everything downstream (the frozen overlay, crops, and
        // final output) get upscaled/blurry. `CGDisplayMode.pixelWidth` /
        // `.pixelHeight` report the true native framebuffer pixel size and
        // must be used instead.
        let mode = CGDisplayCopyDisplayMode(scDisplay.displayID)
        let pixelWidth = mode?.pixelWidth ?? CGDisplayPixelsWide(scDisplay.displayID)
        let pixelHeight = mode?.pixelHeight ?? CGDisplayPixelsHigh(scDisplay.displayID)

        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsDisplay = true

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw classifyCaptureError(error)
        }

        // Contract: the frozen image's point size must equal the screen's
        // point frame, so overlay drawing and selection->pixel math line up
        // even on scaled Retina modes where native pixels != points x
        // backingScaleFactor (e.g. "More Space": 1800pt frame on a 3024px
        // panel). Consumers derive the true pixel/point ratio from
        // cgImage.width / image.size.width — never from backingScaleFactor.
        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }
}

private extension NSScreen {
    /// The `CGDirectDisplayID` backing this screen, used to match against
    /// `SCDisplay.displayID`.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
