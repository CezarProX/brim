// AppSettings+Shell.swift
// Brim
//
// Typed preferences for how the island opens, closes, hides, sizes and moves.

import Foundation

/// Speed presets for every island spring. Durations are multiplied by `durationScale`.
enum ShellAnimationSpeed: String, CaseIterable, Identifiable {
    case turtle, human, cheetah, falcon
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Animation speed multipliers: Turtle 0.7, Human 1, Cheetah 1.5, Falcon 3.
    var speedMultiplier: Double {
        switch self {
        case .turtle: 0.7
        case .human: 1
        case .cheetah: 1.5
        case .falcon: 3
        }
    }

    /// Duration factor for every island spring (1 / speed).
    var durationScale: Double { 1 / speedMultiplier }
}

/// What a right-click on the collapsed notch does.
enum ShellRightClickAction: String, CaseIterable, Identifiable {
    case openSettings, hide, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openSettings: "Open settings"
        case .hide: "Hide for 1 hour"
        case .none: "No action"
        }
    }
}

/// Whether displays without a hardware notch show the island.
enum ShellExternalVisibility: String, CaseIterable, Identifiable {
    case never, whenActive, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: "Never"
        case .whenActive: "When active"
        case .always: "Always"
        }
    }
}

/// How the island looks on a display without a camera cutout.
enum ShellDisplayStyle: String, CaseIterable, Identifiable {
    case notch, island
    var id: String { rawValue }
    var title: String { self == .notch ? "Notch" : "Dynamic Island" }
}

extension AppSettings {
    enum ShellKey {
        static let opensOnHover = "shellOpensOnHover"
        static let openDelay = "shellOpenDelay"
        static let autoCollapse = "shellAutoCollapse"
        static let collapseDelay = "shellCollapseDelay"
        static let autoExpand = "shellAutoExpandActivities"
        static let rightClick = "shellRightClickAction"
        static let speed = "shellAnimationSpeed"
        static let haptics = "shellHaptics"
        static let hideOnFullscreen = "shellHideOnFullscreen"
        static let hideInMissionControl = "shellHideInMissionControl"
        static let hiddenApps = "shellHiddenAppBundleIDs"
        static let hideFromCapture = "shellHideFromScreenSharing"
        static let externalVisibility = "shellExternalVisibility"
        static let externalStyle = "shellExternalStyle"
        static let islandWidth = "shellIslandWidthOffset"
        static let islandHeight = "shellIslandHeightOffset"
        static let islandPosition = "shellIslandVerticalOffset"
        static let notchWidth = "shellNotchWidthOffset"
        static let notchHeight = "shellNotchHeightOffset"
        static let swipeNavigation = "shellSwipeNavigation"
        static let toggleHotkey = "shellToggleHotkeyEnabled"
    }

    /// Slider limits, shared by the settings UI and the clamping getters.
    enum ShellRange {
        static let openDelay: ClosedRange<Double> = 0...1
        static let collapseDelay: ClosedRange<Double> = 0.05...2
        static let islandWidth: ClosedRange<Double> = -40...120
        static let islandHeight: ClosedRange<Double> = -8...16
        static let islandPosition: ClosedRange<Double> = -4...40
        static let notchWidth: ClosedRange<Double> = -40...120
        static let notchHeight: ClosedRange<Double> = -6...12
    }

    private func shellBool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func shellDouble(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        let value = defaults.object(forKey: key) as? Double ?? fallback
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func shellEnum<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    var shellOpensOnHover: Bool {
        get { shellBool(ShellKey.opensOnHover, true) }
        set { defaults.set(newValue, forKey: ShellKey.opensOnHover) }
    }
    /// Seconds the pointer must rest on the notch before it opens (existing behavior: 0.12).
    var shellOpenDelay: Double {
        get { shellDouble(ShellKey.openDelay, 0.25, ShellRange.openDelay) }
        set { defaults.set(newValue, forKey: ShellKey.openDelay) }
    }
    var shellAutoCollapse: Bool {
        get { shellBool(ShellKey.autoCollapse, true) }
        set { defaults.set(newValue, forKey: ShellKey.autoCollapse) }
    }
    /// Seconds the pointer must stay away before the island closes (existing behavior: 0.28).
    var shellCollapseDelay: Double {
        get { shellDouble(ShellKey.collapseDelay, 0.10, ShellRange.collapseDelay) }
        set { defaults.set(newValue, forKey: ShellKey.collapseDelay) }
    }
    /// Briefly open for newly started recordings, timers and calls.
    var shellAutoExpandActivities: Bool {
        get { shellBool(ShellKey.autoExpand, true) }
        set { defaults.set(newValue, forKey: ShellKey.autoExpand) }
    }
    var shellRightClickAction: ShellRightClickAction {
        get { shellEnum(ShellKey.rightClick, .openSettings) }
        set { defaults.set(newValue.rawValue, forKey: ShellKey.rightClick) }
    }
    var shellAnimationSpeed: ShellAnimationSpeed {
        get { shellEnum(ShellKey.speed, .human) }
        set { defaults.set(newValue.rawValue, forKey: ShellKey.speed) }
    }
    var shellHaptics: Bool {
        get { shellBool(ShellKey.haptics, true) }
        set { defaults.set(newValue, forKey: ShellKey.haptics) }
    }
    var shellHideOnFullscreen: Bool {
        get { shellBool(ShellKey.hideOnFullscreen, true) }
        set { defaults.set(newValue, forKey: ShellKey.hideOnFullscreen) }
    }
    var shellHideInMissionControl: Bool {
        get { shellBool(ShellKey.hideInMissionControl, false) }
        set { defaults.set(newValue, forKey: ShellKey.hideInMissionControl) }
    }
    var shellHiddenApps: [String] {
        get { defaults.stringArray(forKey: ShellKey.hiddenApps) ?? [] }
        set { defaults.set(newValue, forKey: ShellKey.hiddenApps) }
    }
    var shellHideFromCapture: Bool {
        get { shellBool(ShellKey.hideFromCapture, false) }
        set { defaults.set(newValue, forKey: ShellKey.hideFromCapture) }
    }
    var shellExternalVisibility: ShellExternalVisibility {
        get { shellEnum(ShellKey.externalVisibility, .always) }
        set { defaults.set(newValue.rawValue, forKey: ShellKey.externalVisibility) }
    }
    var shellExternalStyle: ShellDisplayStyle {
        get { shellEnum(ShellKey.externalStyle, .island) }
        set { defaults.set(newValue.rawValue, forKey: ShellKey.externalStyle) }
    }
    var shellIslandWidthOffset: Double {
        get { shellDouble(ShellKey.islandWidth, 0, ShellRange.islandWidth) }
        set { defaults.set(newValue, forKey: ShellKey.islandWidth) }
    }
    var shellIslandHeightOffset: Double {
        get { shellDouble(ShellKey.islandHeight, 0, ShellRange.islandHeight) }
        set { defaults.set(newValue, forKey: ShellKey.islandHeight) }
    }
    var shellIslandVerticalOffset: Double {
        get { shellDouble(ShellKey.islandPosition, 0, ShellRange.islandPosition) }
        set { defaults.set(newValue, forKey: ShellKey.islandPosition) }
    }
    var shellNotchWidthOffset: Double {
        get { shellDouble(ShellKey.notchWidth, 0, ShellRange.notchWidth) }
        set { defaults.set(newValue, forKey: ShellKey.notchWidth) }
    }
    var shellNotchHeightOffset: Double {
        get { shellDouble(ShellKey.notchHeight, 0, ShellRange.notchHeight) }
        set { defaults.set(newValue, forKey: ShellKey.notchHeight) }
    }
    var shellSwipeNavigation: Bool {
        get { shellBool(ShellKey.swipeNavigation, true) }
        set { defaults.set(newValue, forKey: ShellKey.swipeNavigation) }
    }
    var shellToggleHotkeyEnabled: Bool {
        get { shellBool(ShellKey.toggleHotkey, true) }
        set { defaults.set(newValue, forKey: ShellKey.toggleHotkey) }
    }
}
