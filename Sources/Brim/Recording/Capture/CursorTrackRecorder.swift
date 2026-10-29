// CursorTrackRecorder.swift
// Brim
//
// Logs the pointer while recording, without CGEvent taps or Accessibility: NSEvent monitors for
// moves and button presses (global for other apps, local for our own windows) plus a light poll
// that fills gaps. Times are host-clock seconds so `CursorTrackBuilder` can align them with the
// video through the writer's `RecordingClock`.

import AppKit

@MainActor
final class CursorTrackRecorder {
    private var events: [RawPointerEvent] = []
    private var monitors: [Any] = []
    private var poll: Timer?
    /// NSEvent timestamps count from boot; this converts them to host-clock seconds.
    private let eventToHost = HostClock.now() - ProcessInfo.processInfo.systemUptime
    private static let maxEvents = 400_000

    private static let mask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]

    func start() {
        stop()
        events.removeAll(keepingCapacity: true)
        record(kind: .move, host: HostClock.now(), location: NSEvent.mouseLocation)
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleIfMoved() }
        }
    }

    /// Stops logging and returns everything seen.
    @discardableResult
    func stop() -> [RawPointerEvent] {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        poll?.invalidate()
        poll = nil
        return events
    }

    private func handle(_ event: NSEvent) {
        // Global-monitor events have no window and already carry screen coordinates.
        let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        let host = event.timestamp + eventToHost
        let button = event.buttonNumber
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: record(kind: .down(button), host: host, location: location)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: record(kind: .up(button), host: host, location: location)
        default: record(kind: .move, host: host, location: location)
        }
    }

    private func sampleIfMoved() {
        let location = NSEvent.mouseLocation
        let global = Self.globalTopLeft(location)
        guard let last = events.last, abs(last.x - global.x) > 0.25 || abs(last.y - global.y) > 0.25 else { return }
        record(kind: .move, host: HostClock.now(), location: location)
    }

    private func record(kind: RawPointerEvent.Kind, host: Double, location: NSPoint) {
        guard events.count < Self.maxEvents else { return }
        let global = Self.globalTopLeft(location)
        events.append(RawPointerEvent(host: host, x: global.x, y: global.y, kind: kind))
    }

    /// AppKit's global space has its origin at the primary display's bottom-left; CoreGraphics and
    /// ScreenCaptureKit use the top-left.
    static func globalTopLeft(_ point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
