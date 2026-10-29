import Foundation

/// What the closed island shows right now. Resolved in one pure place so the shell, the
/// controller's hit-testing and the tests all agree on the priority:
/// recording > call > HUD flash > notification > agent needing input > timer/dictation > music > glances.
enum CompactRoute: Equatable {
    /// Nothing live: the wings may carry glances.
    case idle
    case activity(IslandActivity)
    /// A transient volume/brightness/drive/network flash, drawn by `HUDMorphView`.
    case hud(IslandFlash)
    case notification

    var isHUD: Bool { if case .hud = self { return true } else { return false } }

    var hudFlash: IslandFlash? { if case .hud(let flash) = self { return flash }; return nil }

    /// A coding agent that needs the user leads the compact island.
    func isAgentNeedingInput(_ activities: IslandActivities) -> Bool {
        self == .activity(.agent) && activities.agentNeedsInput
    }

    static func resolve(activities: IslandActivities, flash: IslandFlash?, hasNotification: Bool) -> CompactRoute {
        // `.system` is the activity the flash itself raises; the HUD route replaces its compact look.
        let primary = activities.primary == .system ? activities.available.first { $0 != .system } : activities.primary
        if primary == .recording || primary == .call { return .activity(primary!) }
        if let flash { return .hud(flash) }
        if hasNotification { return .notification }
        guard let primary else { return .idle }
        return .activity(primary)
    }
}
