import AppKit
import ApplicationServices
import Foundation

enum NativeTimerAction: Equatable, Sendable {
    case pause
    case resume
    case cancel
}

enum NativeTimerControlResult: Equatable, Sendable {
    case success
    case accessibilityPermissionRequired
    case staleTimer
    case unavailable(String)
    case failed(String)
}

enum NativeTimerControlCapability: Equatable, Sendable {
    case available
    case accessibilityPermissionRequired
    case unavailable(String)
}

struct NativeTimerControlEvidence: Equatable, Sendable {
    let title: String
    let remaining: TimeInterval

    func matches(_ timer: NativeTimerActivity, now: Date, tolerance: TimeInterval) -> Bool {
        title == timer.title && abs(remaining - timer.remaining(at: now)) <= tolerance
    }
}

/// Controls the public Clock UI through macOS Accessibility. The SQLite timer
/// store remains read-only and is used only to reject stale or ambiguous actions.
enum NativeTimerControls {
    private static let clockBundleIdentifier = "com.apple.clock"
    private static let timerContainerIdentifier = "single-timer-1"
    private static let cancelIdentifier = "CancelButton"
    private static let pauseResumeIdentifier = "PauseResumeButton"
    private static let timersTabDescription = "Timers"
    private static let maximumNodes = 96

    static func perform(_ action: NativeTimerAction, expected: NativeTimerActivity) async -> NativeTimerControlResult {
        guard AXIsProcessTrusted() else { return .accessibilityPermissionRequired }
        let candidates = await Task.detached(priority: .utility) { NativeTimerProbe.scanAll() }.value
        guard candidates.count <= 1 else {
            return .unavailable("Clock has multiple active timers, so this timer cannot be controlled safely.")
        }
        guard let fresh = uniqueFresh(expected: expected, candidates: candidates, action: action) else {
            return .staleTimer
        }
        guard let application = await openClockWithoutActivation() else {
            return .unavailable("Clock could not be opened for timer control.")
        }
        let pid = application.processIdentifier
        let result = await Task.detached(priority: .userInitiated) {
            press(action, expected: fresh, pid: pid)
        }.value
        guard result == .success else { return result }
        return await verify(action, expectedID: expected.id) ? .success
            : .failed("Clock did not confirm the timer action.")
    }

    static func matchesFresh(expected: NativeTimerActivity, fresh: NativeTimerActivity,
                             action: NativeTimerAction) -> Bool {
        guard expected.id == fresh.id, expected.title == fresh.title,
              abs(expected.duration - fresh.duration) < 0.001 else { return false }
        switch action {
        case .pause: return !expected.isPaused && !fresh.isPaused
        case .resume: return expected.isPaused && fresh.isPaused
        case .cancel: return expected.isPaused == fresh.isPaused
        }
    }

    static func uniqueFresh(expected: NativeTimerActivity, candidates: [NativeTimerActivity],
                            action: NativeTimerAction) -> NativeTimerActivity? {
        guard candidates.count == 1, let fresh = candidates.first,
              matchesFresh(expected: expected, fresh: fresh, action: action) else { return nil }
        return fresh
    }

    @MainActor
    private static func openClockWithoutActivation() async -> NSRunningApplication? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        let url = URL(fileURLWithPath: "/System/Applications/Clock.app")
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, _ in
                continuation.resume(returning: application?.bundleIdentifier == clockBundleIdentifier ? application : nil)
            }
        }
    }

    private static func press(_ action: NativeTimerAction, expected: NativeTimerActivity,
                              pid: pid_t) -> NativeTimerControlResult {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        for attempt in 0..<8 {
            if let result = pressVisibleControl(action, expected: expected, application: app, pid: pid) { return result }
            _ = selectTimersTab(application: app, pid: pid)
            if attempt < 7 { Thread.sleep(forTimeInterval: 0.08) }
        }
        return .unavailable("Clock did not expose the expected timer control.")
    }

    private static func selectTimersTab(application: AXUIElement, pid: pid_t) -> Bool {
        let windows = elements(application, attribute: kAXWindowsAttribute, maximum: 4)
        let matches = windows.flatMap { descendants($0) }.filter {
            attribute($0, kAXRoleAttribute) as? String == kAXRadioButtonRole
                && attribute($0, kAXDescriptionAttribute) as? String == timersTabDescription
        }
        guard matches.count == 1, let tab = matches.first, isEnabled(tab), supportsPress(tab) else { return false }
        if (attribute(tab, kAXValueAttribute) as? NSNumber)?.boolValue == true { return true }
        var tabPID: pid_t = 0
        return AXUIElementGetPid(tab, &tabPID) == .success && tabPID == pid
            && AXUIElementPerformAction(tab, kAXPressAction as CFString) == .success
    }

    private static func pressVisibleControl(_ action: NativeTimerAction, expected: NativeTimerActivity,
                                            application: AXUIElement, pid: pid_t) -> NativeTimerControlResult? {
        let windows = elements(application, attribute: kAXWindowsAttribute, maximum: 4)
        let containers = windows.flatMap { descendants($0) }.filter {
            attribute($0, kAXIdentifierAttribute) as? String == timerContainerIdentifier
        }
        guard containers.count == 1, let container = containers.first else { return nil }
        let nodes = descendants(container)
        let titles = nodes.compactMap { node -> String? in
            guard attribute(node, kAXRoleAttribute) as? String == kAXTextFieldRole else { return nil }
            return attribute(node, kAXValueAttribute) as? String
        }
        guard titles == [expected.title] else { return .staleTimer }
        let now = Date()
        let tolerance = expected.isPaused ? 1.0 : 4.0
        let evidence = nodes.compactMap { node -> NativeTimerControlEvidence? in
            guard attribute(node, kAXRoleAttribute) as? String == kAXStaticTextRole,
                  let text = attribute(node, kAXDescriptionAttribute) as? String,
                  let seconds = parseClockTime(text) else { return nil }
            return NativeTimerControlEvidence(title: expected.title, remaining: seconds)
        }.filter { $0.matches(expected, now: now, tolerance: tolerance) }
        guard evidence.count == 1 else { return .staleTimer }
        let identifier = action == .cancel ? cancelIdentifier : pauseResumeIdentifier
        let controls = nodes.filter {
            attribute($0, kAXRoleAttribute) as? String == kAXButtonRole
                && attribute($0, kAXIdentifierAttribute) as? String == identifier
        }
        guard controls.count == 1, let control = controls.first, isEnabled(control), supportsPress(control) else {
            return .failed("Clock did not expose the expected timer control.")
        }
        guard uniqueFresh(expected: expected, candidates: NativeTimerProbe.scanAll(), action: action) != nil else {
            return .staleTimer
        }
        var controlPID: pid_t = 0
        guard AXUIElementGetPid(control, &controlPID) == .success, controlPID == pid,
              AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else {
            return .failed("Clock rejected the timer action.")
        }
        return .success
    }

    private static func verify(_ action: NativeTimerAction, expectedID: String) async -> Bool {
        for attempt in 0..<12 {
            let timer = await Task.detached(priority: .utility) { NativeTimerProbe.scan() }.value
            switch action {
            case .pause where timer?.id == expectedID && timer?.isPaused == true: return true
            case .resume where timer?.id == expectedID && timer?.isPaused == false: return true
            case .cancel where timer?.id != expectedID: return true
            default: break
            }
            if attempt < 11 { try? await Task.sleep(for: .milliseconds(80)) }
        }
        return false
    }

    private static func parseClockTime(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 >= 0 }) else { return nil }
        if parts.count == 2 {
            guard parts[1] < 60 else { return nil }
            return TimeInterval(parts[0] * 60 + parts[1])
        }
        guard parts[1] < 60, parts[2] < 60 else { return nil }
        return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
    }

    private static func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root]
        var index = 0
        while index < queue.count, queue.count < maximumNodes {
            let node = queue[index]
            index += 1
            queue.append(contentsOf: elements(node, attribute: kAXChildrenAttribute,
                                               maximum: maximumNodes - queue.count))
        }
        return queue
    }

    private static func elements(_ node: AXUIElement, attribute name: String,
                                 maximum: Int) -> [AXUIElement] {
        guard maximum > 0 else { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(node, name as CFString, 0, maximum, &values) == .success else {
            return []
        }
        return values as? [AXUIElement] ?? []
    }

    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func isEnabled(_ node: AXUIElement) -> Bool {
        (attribute(node, kAXEnabledAttribute) as? Bool) == true
    }

    private static func supportsPress(_ node: AXUIElement) -> Bool {
        var actions: CFArray?
        return AXUIElementCopyActionNames(node, &actions) == .success
            && ((actions as? [String]) ?? []).contains(kAXPressAction)
    }
}
