import AppKit

/// Click, right-click and trackpad-scroll events for the island. Global monitors see events aimed at
/// other apps (the collapsed panel ignores the mouse), local monitors see our own windows.
@MainActor
final class ShellInputMonitor {
    var onLeftClick: ((CGPoint) -> Void)?
    var onRightClick: ((CGPoint) -> Void)?
    /// dx, dy, phase and pointer location of a trackpad scroll.
    var onScroll: ((CGFloat, CGFloat, SwipeTracker.Phase, CGPoint) -> Void)?
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let snapshot = Snapshot(event)
            MainActor.assumeIsolated { self?.dispatch(snapshot) }
        }) { monitors.append(global) }
        // Clicks inside our own windows: only the island's panels matter here, and the island's
        // reaction runs after AppKit has delivered the click. Handling it synchronously inside the
        // monitor made AppKit drop the mouse-down for every other window of the app (capture
        // overlay, onboarding, Settings), so their clicks did nothing.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard event.window == nil || event.window is NSPanel else { return event }
            let snapshot = Snapshot(event)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.dispatch(snapshot) } }
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private struct Snapshot {
        let type: NSEvent.EventType
        let location: CGPoint
        let dx: CGFloat, dy: CGFloat
        let phase: SwipeTracker.Phase?

        init(_ event: NSEvent) {
            type = event.type
            location = NSEvent.mouseLocation
            // Scroll deltas exist only on scroll events: reading them from a click raises an
            // AppKit exception inside the monitor, and AppKit then drops that mouse-down.
            let isScroll = event.type == .scrollWheel
            dx = isScroll ? event.scrollingDeltaX : 0
            dy = isScroll ? event.scrollingDeltaY : 0
            if event.type == .scrollWheel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty {
                if event.phase.contains(.began) { phase = .began }
                else if event.phase.contains(.changed) { phase = .changed }
                else if event.phase.contains(.ended) || event.phase.contains(.cancelled) { phase = .ended }
                else { phase = nil }
            } else {
                phase = nil
            }
        }
    }

    private func dispatch(_ event: Snapshot) {
        switch event.type {
        case .leftMouseDown: onLeftClick?(event.location)
        case .rightMouseDown: onRightClick?(event.location)
        case .scrollWheel:
            if let phase = event.phase { onScroll?(event.dx, event.dy, phase, event.location) }
        default: break
        }
    }
}
