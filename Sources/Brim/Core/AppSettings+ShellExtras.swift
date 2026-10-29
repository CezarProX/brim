// AppSettings+ShellExtras.swift
// Brim
//
// Island shell options beyond opening/closing: what a notch click does, the navigation capsule,
// hold-to-reveal, per-display visibility, open size, pinned favorites and the menu-bar band.

import Foundation

/// What a click on the closed notch does (Settings > Island > "On notch click").
enum ShellClickAction: String, CaseIterable, Identifiable {
    case open, openPage, playPause, nothing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open the island"
        case .openPage: "Open to a chosen page"
        case .playPause: "Play / pause"
        case .nothing: "Do nothing"
        }
    }
}

/// Modifier held near the top of the display to open the island while hover-open is off.
enum ShellRevealModifier: String, CaseIterable, Identifiable {
    case none, option, control, shift, command
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Off"
        case .option: "Hold ⌥"
        case .control: "Hold ⌃"
        case .shift: "Hold ⇧"
        case .command: "Hold ⌘"
        }
    }
}

/// Regular or enlarged open island.
enum ShellOpenSize: String, CaseIterable, Identifiable {
    case regular, enlarged
    var id: String { rawValue }
    var title: String { self == .regular ? "Regular" : "Enlarged" }
    /// Factor applied to the whole open island.
    var scale: Double { self == .regular ? 1 : 1.18 }
}

extension AppSettings {
    enum ShellExtraKey {
        static let clickAction = "shellNotchClickAction"
        static let clickPage = "shellNotchClickPage"
        static let showNavigation = "shellShowNavigation"
        static let revealModifier = "shellRevealModifier"
        static let disabledDisplays = "shellDisabledDisplayUUIDs"
        static let openSize = "shellOpenSize"
        static let favorites = "shellPinnedFavorites"
        static let hidePhysicalNotch = "shellHidePhysicalNotch"
    }

    /// Most widgets that can sit beside the navigation capsule.
    static let shellMaxFavorites = 4

    var shellClickAction: ShellClickAction {
        get { defaults.string(forKey: ShellExtraKey.clickAction).flatMap(ShellClickAction.init(rawValue:)) ?? .open }
        set { defaults.set(newValue.rawValue, forKey: ShellExtraKey.clickAction) }
    }

    /// Raw `IslandPage` name used by "Open to a chosen page": home, clipboard, tray, music, widgets or messages.
    var shellClickPage: String {
        get { defaults.string(forKey: ShellExtraKey.clickPage) ?? "home" }
        set { defaults.set(newValue, forKey: ShellExtraKey.clickPage) }
    }

    var shellShowNavigation: Bool {
        get { defaults.object(forKey: ShellExtraKey.showNavigation) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ShellExtraKey.showNavigation) }
    }

    var shellRevealModifier: ShellRevealModifier {
        get { defaults.string(forKey: ShellExtraKey.revealModifier).flatMap(ShellRevealModifier.init(rawValue:)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: ShellExtraKey.revealModifier) }
    }

    /// UUIDs of displays that must not show the island.
    var shellDisabledDisplays: [String] {
        get { defaults.stringArray(forKey: ShellExtraKey.disabledDisplays) ?? [] }
        set { defaults.set(newValue, forKey: ShellExtraKey.disabledDisplays) }
    }

    var shellOpenSize: ShellOpenSize {
        get { defaults.string(forKey: ShellExtraKey.openSize).flatMap(ShellOpenSize.init(rawValue:)) ?? .regular }
        set { defaults.set(newValue.rawValue, forKey: ShellExtraKey.openSize) }
    }

    /// Widget tile raw values pinned beside the navigation capsule, in order, capped at four.
    var shellPinnedFavorites: [String] {
        get { Array((defaults.stringArray(forKey: ShellExtraKey.favorites) ?? []).prefix(Self.shellMaxFavorites)) }
        set { defaults.set(Array(newValue.prefix(Self.shellMaxFavorites)), forKey: ShellExtraKey.favorites) }
    }

    /// Paints the menu-bar strip beside the camera housing black so the notch disappears into it.
    var shellHidePhysicalNotch: Bool {
        get { defaults.object(forKey: ShellExtraKey.hidePhysicalNotch) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ShellExtraKey.hidePhysicalNotch) }
    }
}
