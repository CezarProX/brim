import AppKit
import ApplicationServices

struct CallProcess {
    let pid: pid_t
    let app: CallApp
    let isBrowser: Bool
}

struct CallControl {
    let element: AXUIElement
    let label: String
}

struct CallSnapshot {
    let process: CallProcess
    let window: AXUIElement
    let scope: AXUIElement
    let title: String
    let controls: [CallControl]
    let evidence: CallEvidence
}

enum CallAction { case mute, camera, screenShare, leave }

/// Runs on the model's serial background queue. Reads are restricted to opted-in
/// call applications, with strict traversal and time budgets; no UI text is stored.
enum CallAccessibilityBridge {
    static let browserIDs: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
                                          "com.brave.Browser", "company.thebrowser.Browser"]

    static func scan(_ processes: [CallProcess]) -> CallSnapshot? {
        let deadline = Date().addingTimeInterval(1.5)
        for process in processes {
            guard Date() < deadline else { break }
            let application = AXUIElementCreateApplication(process.pid)
            AXUIElementSetMessagingTimeout(application, 0.12)
            let windows: [AXUIElement]
            if process.isBrowser {
                windows = element(application, kAXFocusedWindowAttribute).map { [$0] } ?? []
            } else {
                windows = children(application, attribute: kAXWindowsAttribute, maximum: 4)
            }
            for window in windows {
                let scopes = process.isBrowser ? meetScopes(application, window: window, deadline: deadline) : [window]
                for scope in scopes {
                    guard let controls = controls(in: scope, deadline: deadline),
                          let evidence = CallEvidence.detect(app: process.app, buttons: controls.map(\.label)) else { continue }
                    let title = (attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(100)) }
                    return CallSnapshot(process: process, window: window, scope: scope,
                                        title: title ?? "Active call", controls: controls, evidence: evidence)
                }
            }
        }
        return nil
    }

    static func perform(_ action: CallAction, snapshot: CallSnapshot, authorization: CallAuthorizationGate, token: UUID) -> Bool {
        guard AXIsProcessTrusted(),
              let current = scan([snapshot.process]), CFEqual(snapshot.window, current.window),
              CFEqual(snapshot.scope, current.scope), snapshot.title == current.title else { return false }
        let target: String?
        switch action {
        case .mute:
            guard snapshot.evidence.muteLabel == current.evidence.muteLabel else { return false }
            target = current.evidence.muteLabel
        case .camera:
            guard snapshot.evidence.cameraLabel == current.evidence.cameraLabel else { return false }
            target = current.evidence.cameraLabel
        case .screenShare:
            guard snapshot.evidence.screenShareLabel == current.evidence.screenShareLabel,
                  snapshot.evidence.isScreenSharing == current.evidence.isScreenSharing else { return false }
            target = current.evidence.screenShareLabel
        case .leave:
            guard snapshot.evidence.endLabel == current.evidence.endLabel else { return false }
            target = current.evidence.endLabel
        }
        guard let target else { return false }
        let matches = current.controls.filter { CallEvidence.normalize($0.label) == target }
        guard matches.count == 1, let control = matches.first,
              isEnabled(control.element), normalizedLabel(control.element) == target else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(control.element, &pid) == .success, pid == snapshot.process.pid else { return false }
        return authorization.perform(token: token) {
            AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success
        }
    }

    private static func controls(in root: AXUIElement, deadline: Date) -> [CallControl]? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var results: [CallControl] = []
        while index < queue.count {
            guard index < 320, Date() < deadline else { return nil }
            let (node, depth) = queue[index]
            index += 1
            let role = attribute(node, kAXRoleAttribute) as? String
            if role == kAXButtonRole || role == kAXCheckBoxRole {
                if isEnabled(node), let label = normalizedLabel(node), supportsPress(node) {
                    results.append(CallControl(element: node, label: label))
                }
            }
            let descendants = children(node, maximum: 80)
            guard let childCount = childCount(node), childCount == descendants.count else { return nil }
            guard depth < 12 || descendants.isEmpty else { return nil }
            guard queue.count + descendants.count <= 320 else { return nil }
            queue.append(contentsOf: descendants.map { ($0, depth + 1) })
        }
        return results
    }

    private static func meetScopes(_ application: AXUIElement, window: AXUIElement, deadline: Date) -> [AXUIElement] {
        // Walk up from the browser's focused element. Merely finding a Meet URL
        // somewhere in a browser window could accidentally select a hidden tab.
        var current = element(application, kAXFocusedUIElementAttribute)
        var webArea: AXUIElement?
        for _ in 0..<20 {
            guard let node = current, Date() < deadline else { return [] }
            if CFEqual(node, window) { return webArea.map { [$0] } ?? [] }
            if attribute(node, kAXRoleAttribute) as? String == "AXWebArea" {
                let value = attribute(node, "AXURL") ?? attribute(node, kAXDocumentAttribute)
                let url = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                guard CallEvidence.isMeetURL(url) else { return [] }
                webArea = node
            }
            current = element(node, kAXParentAttribute)
        }
        return []
    }

    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func children(_ node: AXUIElement, attribute name: String = kAXChildrenAttribute, maximum: Int) -> [AXUIElement] {
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(node, name as CFString, 0, maximum, &result) == .success else { return [] }
        return (result as? [AXUIElement]) ?? []
    }

    private static func childCount(_ node: AXUIElement) -> Int? {
        var count: CFIndex = 0
        let status = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
        if status == .attributeUnsupported || status == .noValue { return 0 }
        return status == .success ? count : nil
    }

    private static func normalizedLabel(_ node: AXUIElement) -> String? {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            if let value = attribute(node, key) as? String, !value.isEmpty {
                if attribute(node, kAXRoleAttribute) as? String == kAXCheckBoxRole {
                    guard let checked = attribute(node, kAXValueAttribute) as? NSNumber,
                          [0, 1].contains(checked.intValue) else { return nil }
                    return CallEvidence.checkboxAction(label: value, checked: checked.boolValue)
                }
                return CallEvidence.normalize(value)
            }
        }
        return nil
    }

    private static func isEnabled(_ node: AXUIElement) -> Bool {
        (attribute(node, kAXEnabledAttribute) as? Bool) == true
    }

    private static func supportsPress(_ node: AXUIElement) -> Bool {
        var actions: CFArray?
        return AXUIElementCopyActionNames(node, &actions) == .success && ((actions as? [String]) ?? []).contains(kAXPressAction)
    }
}
