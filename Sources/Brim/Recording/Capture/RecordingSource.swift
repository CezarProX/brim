// RecordingSource.swift
// Brim
//
// What to record — a whole display, one window, or an area of a display — resolved into a
// ScreenCaptureKit filter, a stream size and the captured rectangle in global top-left points
// (the space pointer events are normalised against).

import AppKit
import ScreenCaptureKit

enum RecordingSourceKind: String, CaseIterable, Sendable {
    case display, window, area

    var title: String {
        switch self {
        case .display: "Display"
        case .window: "Window"
        case .area: "Area"
        }
    }

    var symbol: String {
        switch self {
        case .display: "display"
        case .window: "macwindow"
        case .area: "rectangle.dashed"
        }
    }
}

enum RecordingTarget {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    /// `rect` is in the display's own top-left point space.
    case area(CGDirectDisplayID, CGRect)

    var kind: RecordingMetadata.Source {
        switch self {
        case .display: .display
        case .window: .window
        case .area: .area
        }
    }
}

/// A target resolved against live ScreenCaptureKit content.
struct ResolvedRecordingTarget {
    let filter: SCContentFilter
    /// Region of the display to capture (display-local points), nil for the whole display/window.
    let sourceRect: CGRect?
    /// Captured area in global top-left points.
    let captureRect: CGRect
    let pixelSize: CGSize
    let pointSize: CGSize
    let kind: RecordingMetadata.Source
}

enum RecordingSourceResolver {
    enum ResolveError: LocalizedError {
        case missing

        var errorDescription: String? { L10n.tr("The display or window to record is no longer available.") }
    }

    static func resolve(_ target: RecordingTarget, retina: Bool) async throws -> ResolvedRecordingTarget {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        switch target {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw ResolveError.missing }
            let bounds = CGDisplayBounds(id)
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            return ResolvedRecordingTarget(filter: filter, sourceRect: nil, captureRect: bounds,
                                           pixelSize: pixels(bounds.size, display: id, retina: retina), pointSize: bounds.size, kind: .display)
        case .area(let id, let rect):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw ResolveError.missing }
            let bounds = CGDisplayBounds(id)
            let local = rect.integral.intersection(CGRect(origin: .zero, size: bounds.size))
            guard local.width >= 8, local.height >= 8 else { throw ResolveError.missing }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let global = local.offsetBy(dx: bounds.minX, dy: bounds.minY)
            return ResolvedRecordingTarget(filter: filter, sourceRect: local, captureRect: global,
                                           pixelSize: pixels(local.size, display: id, retina: retina), pointSize: local.size, kind: .area)
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw ResolveError.missing }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let frame = window.frame
            let display = displayID(containing: frame)
            return ResolvedRecordingTarget(filter: filter, sourceRect: nil, captureRect: frame,
                                           pixelSize: pixels(frame.size, display: display, retina: retina), pointSize: frame.size, kind: .window)
        }
    }

    /// Even pixel dimensions at the display's native density (or 1×).
    static func pixels(_ points: CGSize, display: CGDirectDisplayID?, retina: Bool) -> CGSize {
        let scale = retina ? display.map(backingScale) ?? 2 : 1
        let even: (Double) -> Double = { max(2, (($0 * scale) / 2).rounded(.down) * 2) }
        return CGSize(width: even(points.width), height: even(points.height))
    }

    /// Native pixels per point of a display (2 on Retina, also correct for scaled modes).
    static func backingScale(_ display: CGDirectDisplayID) -> Double {
        guard let mode = CGDisplayCopyDisplayMode(display), mode.width > 0 else { return 2 }
        return Double(mode.pixelWidth) / Double(mode.width)
    }

    static func displayID(containing rect: CGRect) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetDisplaysWithRect(rect, 16, &ids, &count) == .success, count > 0 else { return CGMainDisplayID() }
        return ids[0]
    }

    /// The display under the pointer.
    static func displayUnderPointer() -> CGDirectDisplayID {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        return screen?.recordingDisplayID ?? CGMainDisplayID()
    }

    /// Windows worth offering in the picker: normal layer, titled-ish, not ours, reasonably large.
    static func pickableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { window in
            window.windowLayer == 0 && window.frame.width >= 120 && window.frame.height >= 80
                && window.owningApplication?.processID != own && window.owningApplication != nil
        }
    }
}

extension NSScreen {
    var recordingDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
