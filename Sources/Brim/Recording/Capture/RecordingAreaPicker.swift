// RecordingAreaPicker.swift
// Brim
//
// "Drag to select the region to record." A second entry point onto the screenshot overlay's
// building blocks (OverlayWindow + SelectionOverlayView, unchanged): the same frozen, dimmed screen
// and selection chrome, but committing hands back a rectangle instead of opening the annotator.

import AppKit
import SwiftUI

@MainActor
final class RecordingAreaPicker {
    static let shared = RecordingAreaPicker()

    private var windows: [OverlayWindow] = []
    private var views: [NSScreen: SelectionOverlayView] = [:]
    private var activeScreen: NSScreen?
    private var selection: CGRect?
    private var drag: (start: CGPoint, rect: CGRect?, handle: ResizeHandle?)?
    private var confirmBar: NSView?
    private var keyMonitor: Any?
    private var completion: ((CGDirectDisplayID, CGRect)?) -> Void = { _ in }

    var isActive: Bool { !windows.isEmpty }

    /// Shows the picker; `completion` gets the display and its top-left local rect, or nil if cancelled.
    func pick(frozen: [NSScreen: NSImage], completion: @escaping ((CGDirectDisplayID, CGRect)?) -> Void) {
        dismiss()
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.frozenImage = frozen[screen]
            view.onMouseDown = { [weak self] point in self?.mouseDown(screen, point) }
            view.onMouseDragged = { [weak self] point in self?.mouseDragged(screen, point) }
            view.onMouseUp = { [weak self] _ in self?.mouseUp(screen) }
            window.contentView = view
            window.onPerformKeyEquivalent = { [weak self] event in self?.key(event) ?? false }
            views[screen] = view
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let pointer = NSEvent.mouseLocation
        windows.first { $0.screen?.frame.contains(pointer) == true }?.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        confirmBar?.removeFromSuperview()
        confirmBar = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        activeScreen = nil
        selection = nil
        drag = nil
    }

    // MARK: Mouse

    private func mouseDown(_ screen: NSScreen, _ point: CGPoint) {
        if screen == activeScreen, let rect = selection {
            if let handle = ResizeHandle.hitTest(point, in: rect) { drag = (point, rect, handle); return }
            if rect.contains(point) { drag = (point, rect, nil); return }
        }
        activeScreen = screen
        selection = nil
        confirmBar?.removeFromSuperview()
        drag = (point, nil, nil)
        for (other, view) in views {
            view.isActiveScreen = other == screen
            view.selectionRect = nil
            view.liveDragRect = nil
        }
    }

    private func mouseDragged(_ screen: NSScreen, _ point: CGPoint) {
        guard screen == activeScreen, let drag, let view = views[screen] else { return }
        let bounds = view.bounds
        if let rect = drag.rect {
            let delta = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
            var next = drag.handle.map { $0.resized(from: rect, delta: delta).standardized }
                ?? rect.offsetBy(dx: delta.width, dy: delta.height)
            next.origin.x = min(max(next.minX, 0), bounds.maxX - next.width)
            next.origin.y = min(max(next.minY, 0), bounds.maxY - next.height)
            selection = next.intersection(bounds)
            view.selectionRect = selection
            positionConfirmBar()
        } else {
            view.liveDragRect = CGRect(x: min(drag.start.x, point.x), y: min(drag.start.y, point.y),
                                       width: abs(point.x - drag.start.x), height: abs(point.y - drag.start.y))
        }
    }

    private func mouseUp(_ screen: NSScreen) {
        defer { drag = nil }
        guard screen == activeScreen, let view = views[screen], drag?.rect == nil else { return }
        let rect = view.liveDragRect ?? .zero
        view.liveDragRect = nil
        guard rect.width >= 24, rect.height >= 24 else { return }
        selection = rect
        view.selectionRect = rect
        showConfirmBar(on: view)
    }

    // MARK: Confirm

    private func showConfirmBar(on view: NSView) {
        confirmBar?.removeFromSuperview()
        let bar = NSHostingView(rootView: RecordingAreaConfirmBar(
            onRecord: { [weak self] in self?.confirm() }, onCancel: { [weak self] in self?.finish(nil) }))
        bar.frame.size = bar.fittingSize
        view.addSubview(bar)
        confirmBar = bar
        positionConfirmBar()
    }

    private func positionConfirmBar() {
        guard let bar = confirmBar, let rect = selection, let bounds = bar.superview?.bounds else { return }
        let size = bar.fittingSize
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 12)
        if origin.y < 8 { origin.y = rect.minY + 12 }
        origin.x = min(max(origin.x, 8), bounds.maxX - size.width - 8)
        bar.frame = CGRect(origin: origin, size: size)
    }

    private func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: finish(nil); return true
        case 36, 76: confirm(); return selection != nil
        default: return false
        }
    }

    private func confirm() {
        guard let screen = activeScreen, let rect = selection, let id = screen.recordingDisplayID else { return }
        // View space is bottom-left; ScreenCaptureKit's sourceRect is top-left in display points.
        let local = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        finish((id, local))
    }

    private func finish(_ result: (CGDirectDisplayID, CGRect)?) {
        let done = completion
        completion = { _ in }
        dismiss()
        done(result)
    }
}

private struct RecordingAreaConfirmBar: View {
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .background(Circle().fill(.white.opacity(0.12)))
            .help("Cancel")
            Button(action: onRecord) {
                Label("Record", systemImage: "record.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color(red: 1, green: 0.27, blue: 0.23)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(6)
        .background(Capsule().fill(.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }
}
