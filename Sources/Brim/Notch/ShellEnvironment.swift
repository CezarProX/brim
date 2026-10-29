import AppKit
import CoreGraphics

/// What the window server says about one display right now.
struct ShellDisplayState: Equatable {
    var hasFullscreenWindow = false
    var missionControlActive = false
    /// A fullscreen app covers this display, whether or not the shell is set to hide for it.
    /// Media uses this to drop the music activity (Settings > Media).
    var coveredByFullscreen = false
}

/// Samples fullscreen windows, Mission Control and the front app. Polled at a low rate by the controller;
/// the window list is cheap and needs no Screen Recording permission because only bounds are read.
@MainActor
final class ShellEnvironment {
    private(set) var states: [CGDirectDisplayID: ShellDisplayState] = [:]
    private(set) var frontmostBundleID: String?
    private var lastSample: TimeInterval = -.infinity

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// A stable identifier for a display, surviving reconnects (unlike the numeric display ID).
    static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return string
    }

    /// Width and height of the camera housing, or nil for a display without one.
    static func hardwareNotch(of screen: NSScreen) -> (width: CGFloat, height: CGFloat)? {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return (max(0, right.minX - left.maxX), screen.safeAreaInsets.top)
    }

    /// Demo mode only: treat every display as notchless, so the island films as a floating pill.
    static var demoForcesIsland = false

    static func geometry(for screen: NSScreen, settings: AppSettings = .shared) -> NotchGeometry {
        NotchGeometry.make(screenFrame: screen.frame, hardwareNotch: demoForcesIsland ? nil : hardwareNotch(of: screen),
                           style: settings.shellExternalStyle, tuning: .current(settings))
    }

    func state(for id: CGDirectDisplayID?) -> ShellDisplayState {
        id.flatMap { states[$0] } ?? ShellDisplayState()
    }

    /// Re-samples at most every `interval` seconds.
    func refresh(screens: [NSScreen], now: TimeInterval, interval: TimeInterval = 0.4) {
        guard now - lastSample >= interval else { return }
        lastSample = now
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let settings = AppSettings.shared
        guard settings.shellHideOnFullscreen || settings.shellHideInMissionControl || settings.hideMediaInFullscreen else {
            states = [:]
            return
        }
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var next: [CGDirectDisplayID: ShellDisplayState] = [:]
        for screen in screens {
            guard let id = Self.displayID(of: screen) else { continue }
            let display = CGDisplayBounds(id)
            let samples = info.compactMap(Self.sample)
            let menuBar = info.contains { entry in
                guard entry["kCGWindowOwnerName"] as? String == "Window Server", entry["kCGWindowLayer"] as? Int == 24,
                      let bounds = Self.bounds(entry) else { return false }
                return abs(bounds.minX - display.minX) <= 1 && abs(bounds.minY - display.minY) <= 1
            }
            let dock = info.filter { $0["kCGWindowOwnerName"] as? String == "Dock" && ($0["kCGWindowLayer"] as? Int ?? -1) >= 0 }
                .compactMap(Self.bounds)
            let covered = FullscreenDetector.isCovered(
                display: display, notchHeight: screen.safeAreaInsets.top, menuBarVisible: menuBar,
                windows: samples, ignoringPID: ownPID)
            next[id] = ShellDisplayState(
                hasFullscreenWindow: settings.shellHideOnFullscreen && covered,
                missionControlActive: settings.shellHideInMissionControl
                    && FullscreenDetector.isMissionControl(display: display, dockWindows: dock),
                coveredByFullscreen: covered)
        }
        states = next
    }

    private static func bounds(_ entry: [String: Any]) -> CGRect? {
        (entry["kCGWindowBounds"] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    }

    private static func sample(_ entry: [String: Any]) -> ShellWindowSample? {
        guard let pid = entry["kCGWindowOwnerPID"] as? Int32, let layer = entry["kCGWindowLayer"] as? Int,
              let bounds = bounds(entry) else { return nil }
        return ShellWindowSample(pid: pid, layer: layer, bounds: bounds)
    }
}

/// Alignment-style haptic tick on trackpads; silent elsewhere.
enum ShellHaptics {
    @MainActor static func tick() {
        guard AppSettings.shared.shellHaptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
