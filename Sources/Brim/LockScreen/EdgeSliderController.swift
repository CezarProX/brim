import AppKit
import SwiftUI

/// Shows the edge slider on the left edge of the screen when a volume or brightness key is pressed.
/// On the lock screen the panel is delegated into the SkyLight space (via `lockBridge`); on the desktop
/// it is an ordinary floating panel. Both are optional in settings.
@MainActor
final class EdgeSliderController: ObservableObject {
    static let shared = EdgeSliderController()
    static let edgeInset: CGFloat = 14

    @Published private(set) var kind: EdgeSliderKind = .volume
    @Published private(set) var level = 0.0
    @Published private(set) var muted = false
    @Published private(set) var style: EdgeSliderSession.Style = .wide

    /// Set while the lock screen is up; the panel then goes above the login window.
    var lockBridge: LockScreenWindowBridge?
    private var session = EdgeSliderSession()
    private var panel: LockScreenPanel?
    private var hideTimer: Timer?
    private var settings: AppSettings { .shared }

    /// Whether a key press should be shown as an edge slider instead of the notch HUD.
    var handlesKeys: Bool { lockBridge != nil ? settings.lockScreenEdgeSliders : settings.desktopEdgeSliders }

    /// Returns true when the slider took over the HUD for this press.
    @discardableResult
    func show(_ kind: EdgeSliderKind, level: Double, muted: Bool = false, now: Date = .now) -> Bool {
        guard handlesKeys else { return false }
        self.kind = kind
        self.level = HUDLevelMath.clamp(level)
        self.muted = muted
        style = session.press(now: now)
        present()
        scheduleHide()
        return true
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }

    private func present() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let size = EdgeSliderView.size(for: .wide)
        let frame = CGRect(x: screen.frame.minX + Self.edgeInset, y: screen.frame.midY - size.height / 2,
                           width: size.width + 24, height: size.height + 24)
        if panel == nil {
            let created = LockScreenPanel(frame: frame)
            created.contentView = NSHostingView(rootView: AnyView(EdgeSliderHost(controller: self)))
            created.ignoresMouseEvents = false
            panel = created
        }
        guard let panel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.level = lockBridge == nil ? .statusBar : LockScreenPanel.desiredLevel
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if let lockBridge { _ = lockBridge.delegate(panel) }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: EdgeSliderSession.visibleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fadeOut() }
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { Task { @MainActor in panel.orderOut(nil) } })
    }

    /// Slider dragged by the user.
    fileprivate func dragged(_ value: Double) {
        level = value
        switch kind {
        case .volume: _ = SystemVolumeControl.setLevel(value)
        case .brightness: _ = DisplayBrightnessControl.shared.setLevel(value, display: DisplayBrightnessControl.targetDisplay())
        }
        scheduleHide()
    }
}

private struct EdgeSliderHost: View {
    @ObservedObject var controller: EdgeSliderController
    var body: some View {
        EdgeSliderView(kind: controller.kind, level: controller.level, style: controller.style,
                       tint: controller.kind == .volume ? .white : Color(red: 1, green: 0.84, blue: 0.3),
                       muted: controller.muted, onDrag: { controller.dragged($0) })
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
