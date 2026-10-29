import Foundation

enum IslandActivity: String, CaseIterable {
    case recording, call, timer, music, dictation, focus, calendar, transfer, devices, system, workspace, agent
    case recorder, keepAwake, notes, stats, camera, browser, download, build
    /// Quiet always-on indicators: camera or microphone in use, Focus on, Personal Hotspot connected.
    case privacy, dnd, hotspot

    /// Quiet system state stays in the compact island; it has no expanded activity page.
    var isPassiveStatus: Bool { self == .privacy || self == .dnd || self == .hotspot }

    var title: String {
        switch self {
        case .recording: return "Screen Recording"
        case .call: return "Active call"
        case .timer: return "Timer"
        case .music: return "Music"
        case .dictation: return "Dictation"
        case .focus: return "Focus timer"
        case .calendar: return "Next meeting"
        case .transfer: return "Sharing"
        case .devices: return "Batteries"
        case .system: return "System"
        case .workspace: return "Current app"
        case .agent: return "Agent status"
        case .recorder: return "Voice Memos"
        case .keepAwake: return "Keep Awake"
        case .notes: return "Notes"
        case .stats: return "System Stats"
        case .camera: return "Mirror"
        case .browser: return "Browser"
        case .download: return "Download"
        case .build: return "Xcode build"
        case .privacy: return "Camera or microphone in use"
        case .dnd: return "Focus"
        case .hotspot: return "Personal Hotspot"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "record.circle"
        case .call: return "phone.fill"
        case .timer: return "timer"
        case .music: return "music.note"
        case .dictation: return "mic.fill"
        case .focus: return "hourglass"
        case .calendar: return "calendar"
        case .transfer: return "square.and.arrow.up"
        case .devices: return "battery.100percent"
        case .system: return "slider.horizontal.3"
        case .workspace: return "app"
        case .agent: return "terminal"
        case .recorder: return "waveform"
        case .keepAwake: return "cup.and.saucer.fill"
        case .notes: return "note.text"
        case .stats: return "gauge.with.dots.needle.33percent"
        case .camera: return "camera.fill"
        case .browser: return "safari.fill"
        case .download: return "arrow.down.circle.fill"
        case .build: return "hammer.fill"
        case .privacy: return "video.fill"
        case .dnd: return "moon.fill"
        case .hotspot: return "personalhotspot"
        }
    }
}

/// Explicit Brim priority, rather than an inferred private iOS scheduling rule.
struct IslandActivities: Equatable {
    let recording: Bool
    let call: Bool
    let music: Bool
    var timer: Bool = false
    /// A coding agent is blocked on the user; it then ranks just under calls.
    var agentNeedsInput: Bool = false
    var additional: [IslandActivity] = []
    /// The activity the user flicked onto the notch; ignored once it is no longer live.
    var leader: IslandActivity?

    var available: [IslandActivity] {
        let active = Set(additional + [recording ? .recording : nil, call ? .call : nil,
                                      timer ? .timer : nil, music ? .music : nil].compactMap { $0 })
        // Like Now Playing on iPhone, a playing song keeps the island and a timer, meeting or download
        // beside it takes the detached bubble. Only things the user is doing right now (recording,
        // a call, dictating) push the song into the bubble. Ambient skins (coding agents, keep awake,
        // the front browser) rank below it: they describe background state.
        let order: [IslandActivity] = [.recording, .call, .dictation, .recorder, .music, .timer, .focus, .calendar,
                .transfer, .download, .build, .privacy, .agent, .keepAwake, .dnd, .hotspot, .system, .devices, .browser, .workspace]
        let ranked = agentNeedsInput
            ? [.recording, .call, .agent] + order.filter { ![.recording, .call, .agent].contains($0) } : order
        return ranked.filter { active.contains($0) }
    }
    var primary: IslandActivity? {
        if let leader, available.contains(leader) { return leader }
        return available.first
    }
    var secondary: IslandActivity? { companion(to: primary) }

    func selected(_ preferred: IslandActivity?) -> IslandActivity? {
        preferred.flatMap { available.contains($0) ? $0 : nil } ?? primary
    }

    /// What the island itself shows, so no bubble repeats it: closed, the leader; open on the Music
    /// page, the song (whatever card was selected before); open anywhere else, the selected card.
    func islandOwner(expanded: Bool, selected preferred: IslandActivity?, showingMusic: Bool) -> IslandActivity? {
        guard expanded else { return primary }
        return showingMusic && music ? .music : selected(preferred)
    }

    /// App skins describe what's in front; they never claim a bubble.
    static let ambient: Set<IslandActivity> = [.browser, .workspace]

    /// The best-ranked bubble beside `activity`; `companions(to:)` (IslandBubbles.swift) lists both.
    func companion(to activity: IslandActivity?) -> IslandActivity? {
        companions(to: activity).first
    }
}

/// Briefly reveal newly started time-sensitive activities, then return to the compact surface.
struct IslandAnnouncement {
    private var previous: IslandActivity?
    private var until: TimeInterval = 0

    mutating func update(primary: IslandActivity?, now: TimeInterval) -> Bool {
        if primary != previous {
            previous = primary
            until = primary == .recording || primary == .timer || primary == .call ? now + 2.2 : 0
        }
        return now < until
    }

    mutating func dismiss() { until = 0 }
}
