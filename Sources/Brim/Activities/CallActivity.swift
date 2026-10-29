import Foundation

struct CallActivity: Equatable {
    let id: UUID
    let processIdentifier: pid_t
    let appName: String
    let title: String
    /// Time Brim first observed the controls, not the provider's call start time.
    let beganAt: Date
    let isMuted: Bool?
    let isCameraOn: Bool?
    let isScreenSharing: Bool?
}

/// Revoking a connection invalidates queued actions before any AX side effect.
/// The lock also makes revocation atomic with an already-starting button press.
final class CallAuthorizationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var token: UUID?

    func renew() {
        lock.lock()
        defer { lock.unlock() }
        token = UUID()
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }

    func currentToken() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func perform(token expected: UUID, operation: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard token == expected else { return false }
        return operation()
    }
}

enum CallApp: String, CaseIterable {
    case zoom, faceTime, phone, whatsApp, discord, teams, googleMeet

    init?(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "us.zoom.xos": self = .zoom
        case "com.apple.FaceTime": self = .faceTime
        case "com.apple.mobilephone": self = .phone
        case "net.whatsapp.WhatsApp": self = .whatsApp
        case "com.hnc.Discord", "com.hnc.DiscordCanary", "com.hnc.DiscordPTB": self = .discord
        case "com.microsoft.teams", "com.microsoft.teams2": self = .teams
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .faceTime: return "FaceTime"
        case .phone: return "Phone"
        case .whatsApp: return "WhatsApp"
        case .discord: return "Discord"
        case .teams: return "Teams"
        case .googleMeet: return "Google Meet"
        }
    }

    var endLabels: Set<String> {
        switch self {
        case .zoom: return ["leave", "leave meeting", "end meeting"]
        case .discord: return ["disconnect", "disconnect from voice"]
        case .teams: return ["leave", "leave call", "leave meeting", "hang up"]
        case .googleMeet: return ["leave call"]
        case .faceTime, .phone, .whatsApp: return ["end", "end call", "hang up"]
        }
    }

    var startSharingLabels: Set<String> {
        switch self {
        case .zoom: return ["share screen"]
        case .faceTime: return ["share my screen"]
        case .whatsApp: return ["share screen"]
        case .discord: return ["share your screen"]
        case .teams: return ["share content"]
        case .googleMeet: return ["present now"]
        case .phone: return []
        }
    }

    var stopSharingLabels: Set<String> {
        switch self {
        case .zoom: return ["stop share"]
        case .faceTime: return ["stop sharing"]
        case .whatsApp: return ["stop sharing screen"]
        case .discord: return ["stop streaming"]
        case .teams: return ["stop sharing"]
        case .googleMeet: return ["stop presenting"]
        case .phone: return []
        }
    }
}

/// Only exact, unambiguous, enabled controls constitute call evidence. An app name,
/// window title, incoming-call dialog, or a microphone alone is insufficient.
struct CallEvidence: Equatable {
    let endLabel: String
    let muteLabel: String
    let cameraLabel: String?
    let screenShareLabel: String?
    let isMuted: Bool
    let isCameraOn: Bool?
    let isScreenSharing: Bool?

    static func normalize(_ label: String) -> String {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Known keyboard hints belong to the same exact control label.
        let suffixes = [" (⌘ + d)", " (⌘+d)", " (ctrl + d)", " (ctrl+d)",
                        " (⌘ + e)", " (⌘+e)", " (ctrl + e)", " (ctrl+e)",
                        " (⇧⌘a)", " (⇧⌘v)", " (⌘⇧a)", " (⌘⇧v)",
                        " (ctrl+shift+m)", " (ctrl+shift+o)"]
        if let suffix = suffixes.first(where: { normalized.hasSuffix($0) }) {
            return String(normalized.dropLast(suffix.count))
        }
        return normalized
    }

    static func detect(app: CallApp, buttons: [String]) -> CallEvidence? {
        let labels = buttons.map(normalize)
        let endings = labels.filter { app.endLabels.contains($0) }
        let muteOff: Set<String> = ["mute", "mute microphone", "turn off microphone", "mute my audio"]
        let muteOn: Set<String> = ["unmute", "unmute microphone", "turn on microphone", "unmute my audio"]
        let microphones = labels.filter { muteOff.contains($0) || muteOn.contains($0) }
        guard endings.count == 1, microphones.count == 1 else { return nil }
        let cameraOff: Set<String> = ["start video", "turn on camera", "turn camera on", "enable camera"]
        let cameraOn: Set<String> = ["stop video", "turn off camera", "turn camera off", "disable camera"]
        let cameras = labels.filter { cameraOff.contains($0) || cameraOn.contains($0) }
        let camera = cameras.count == 1 ? cameras[0] : nil
        let sharing = labels.filter { app.startSharingLabels.contains($0) || app.stopSharingLabels.contains($0) }
        let screenShare = sharing.count == 1 ? sharing[0] : nil
        return CallEvidence(endLabel: endings[0], muteLabel: microphones[0], cameraLabel: camera,
                            screenShareLabel: screenShare,
                            isMuted: muteOn.contains(microphones[0]),
                            isCameraOn: camera.map { cameraOn.contains($0) },
                            isScreenSharing: screenShare.map { app.stopSharingLabels.contains($0) })
    }

    static func isMeetURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "meet.google.com" else { return false }
        return url.path != "/" && !url.path.isEmpty
    }

    static func checkboxAction(label: String, checked: Bool) -> String? {
        // A checked Mute checkbox means currently muted; its press will unmute.
        let pairs = ["mute": "unmute", "mute microphone": "unmute microphone", "mute my audio": "unmute my audio"]
        let label = normalize(label)
        guard let opposite = pairs[label] else { return nil }
        return checked ? opposite : label
    }
}
