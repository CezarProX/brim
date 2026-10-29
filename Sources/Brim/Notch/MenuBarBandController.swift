import AppKit

/// "Hide physical notch": a black strip behind the menu bar on notched displays, so the camera
/// housing blends into the bar instead of cutting the wallpaper. It sits below the menu bar (its
/// items stay visible) and joins no fullscreen Space, so fullscreen apps are untouched.
@MainActor
final class MenuBarBandController {
    private var panels: [NSPanel] = []
    private var observer: NSObjectProtocol?
    private var enabled = false

    func update(enabled: Bool) {
        self.enabled = enabled
        guard enabled else {
            tearDown()
            return
        }
        rebuild()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                self.rebuild()
            }
        }
    }

    private func tearDown() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        for screen in NSScreen.screens {
            guard let frame = MenuBarBandLayout.frame(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top)
            else { continue }
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.sharingType = .none
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }
}
