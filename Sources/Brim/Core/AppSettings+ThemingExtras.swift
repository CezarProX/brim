// AppSettings+ThemingExtras.swift
// Brim
//
// Glass clarity, Light-mode glass, highlight and window tint colours, and low-battery mode.

import Foundation

extension AppSettings {
    private enum ThemingExtraKey {
        static let clarity = "islandGlassClarity"
        static let lightGlass = "islandLightGlassInLightMode"
        static let highlight = "islandHighlightHex"
        static let windowTint = "islandWindowTintHex"
        static let progressiveBlur = "islandProgressiveBlur"
        static let lowBattery = "islandLowBatteryMode"
    }

    /// 0 = dense, frosted glass; 1 = the clearest glass. 0.5 matches the original look.
    var islandGlassClarity: Double {
        get { min(1, max(0, defaults.object(forKey: ThemingExtraKey.clarity) as? Double ?? 0.5)) }
        set { defaults.set(min(1, max(0, newValue)), forKey: ThemingExtraKey.clarity) }
    }

    /// In macOS Light mode the glass turns pale and frosted instead of staying smoky dark.
    var islandLightGlassInLightMode: Bool {
        get { defaults.object(forKey: ThemingExtraKey.lightGlass) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ThemingExtraKey.lightGlass) }
    }

    /// "#RRGGBB" for selection highlights, sliders and toggles in the island; empty = default.
    var islandHighlightHex: String {
        get { defaults.string(forKey: ThemingExtraKey.highlight) ?? "" }
        set { defaults.set(newValue, forKey: ThemingExtraKey.highlight) }
    }

    /// "#RRGGBB" washed over the glass; empty = none.
    var islandWindowTintHex: String {
        get { defaults.string(forKey: ThemingExtraKey.windowTint) ?? "" }
        set { defaults.set(newValue, forKey: ThemingExtraKey.windowTint) }
    }

    /// A soft blur halo around the open island, fading out into the desktop.
    var islandProgressiveBlur: Bool {
        get { defaults.object(forKey: ThemingExtraKey.progressiveBlur) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ThemingExtraKey.progressiveBlur) }
    }

    /// Automatic lighter visuals (solid black, no blur) on battery under 20% or in Low Power Mode.
    var islandLowBatteryMode: Bool {
        get { defaults.object(forKey: ThemingExtraKey.lowBattery) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ThemingExtraKey.lowBattery) }
    }
}
