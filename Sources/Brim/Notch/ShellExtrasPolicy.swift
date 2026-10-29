import AppKit
import CoreGraphics
import SwiftUI

// Pure decisions for the island shell options: notch click, hold-to-reveal, per-display
// visibility, favorites, the menu-bar band, glass clarity and low-battery mode.

/// What the island does with a click on the collapsed notch.
enum NotchClickOutcome: Equatable {
    case open
    case openPage(IslandPage)
    case togglePlayback
    case ignore
}

enum NotchClickResolver {
    static func resolve(action: ShellClickAction, page: String) -> NotchClickOutcome {
        switch action {
        case .open: .open
        case .openPage: .openPage(IslandPage.fromStored(page))
        case .playPause: .togglePlayback
        case .nothing: .ignore
        }
    }
}

extension IslandPage {
    var storedName: String {
        switch self {
        case .home: "home"
        case .clipboard: "clipboard"
        case .tray: "tray"
        case .music: "music"
        case .widgets: "widgets"
        case .messages: "messages"
        }
    }

    static func fromStored(_ name: String) -> IslandPage {
        allCases.first { $0.storedName == name } ?? .home
    }
}

/// Hold a modifier near the top of the display to open the island while hover-open is off.
enum ShellRevealPolicy {
    /// How far below the top edge, and how far beside the notch, the pointer still counts as "near".
    static let zoneDepth: CGFloat = 44
    static let zoneMargin: CGFloat = 70

    static func flag(for modifier: ShellRevealModifier) -> NSEvent.ModifierFlags? {
        switch modifier {
        case .none: nil
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .command: .command
        }
    }

    static func zone(trigger: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: trigger.minX - zoneMargin, y: screen.maxY - zoneDepth,
               width: trigger.width + 2 * zoneMargin, height: zoneDepth + 1)
    }

    /// True while the chosen modifier is down and the pointer is in the zone.
    static func isRevealing(modifier: ShellRevealModifier, held: NSEvent.ModifierFlags,
                            pointer: CGPoint, zone: CGRect) -> Bool {
        guard let flag = flag(for: modifier), held.contains(flag) else { return false }
        return pointer.x >= zone.minX && pointer.x <= zone.maxX
            && pointer.y >= zone.minY && pointer.y <= zone.maxY
    }
}

/// Widgets pinned beside the navigation capsule.
enum IslandFavorites {
    /// Valid, unique, openable tiles in stored order, at most `AppSettings.shellMaxFavorites`.
    static func tiles(from stored: [String]) -> [IslandWidgetTile] {
        var seen: Set<IslandWidgetTile> = []
        var result: [IslandWidgetTile] = []
        for raw in stored {
            guard let tile = IslandWidgetTile(rawValue: raw), tile.opensInIsland, seen.insert(tile).inserted else { continue }
            result.append(tile)
            if result.count == AppSettings.shellMaxFavorites { break }
        }
        return result
    }

    /// Toggles a pin; a fifth pin is refused (returns the list unchanged).
    static func toggled(_ tile: IslandWidgetTile, in stored: [String]) -> [String] {
        if stored.contains(tile.rawValue) { return stored.filter { $0 != tile.rawValue } }
        guard stored.count < AppSettings.shellMaxFavorites else { return stored }
        return stored + [tile.rawValue]
    }
}

/// The black strip that hides the physical notch: the display's menu-bar height, edge to edge.
enum MenuBarBandLayout {
    static func frame(screenFrame: CGRect, safeAreaTop: CGFloat) -> CGRect? {
        guard safeAreaTop > 0 else { return nil }
        return CGRect(x: screenFrame.minX, y: screenFrame.maxY - safeAreaTop,
                      width: screenFrame.width, height: safeAreaTop)
    }
}

/// Glass density. Clarity 0.5 reproduces the original look exactly.
struct GlassClarity: Equatable {
    let clarity: Double

    init(_ clarity: Double) { self.clarity = min(1, max(0, clarity)) }

    /// Black veil over the blur: double the base at 0, none at 1.
    func veilOpacity(tinted: Bool) -> Double {
        let base = tinted ? 0.32 : 0.08
        return min(0.9, base * 2 * (1 - clarity))
    }

    /// Wallpaper-snapshot blur radius (renders): sharper when clearer. 0.5 -> `base`.
    func blurRadius(base: CGFloat) -> CGFloat {
        base * CGFloat(1.46 - 0.92 * clarity)
    }
}

/// Lighter visuals when the battery is nearly flat or Low Power Mode is on.
enum LowBatteryPolicy {
    static let threshold = 20

    static func isActive(enabled: Bool, percent: Int?, charging: Bool, lowPowerMode: Bool) -> Bool {
        guard enabled else { return false }
        if lowPowerMode { return true }
        guard let percent, !charging else { return false }
        return percent < threshold
    }
}

/// Hex colours stored by the theming settings.
enum IslandHex {
    static func color(_ hex: String) -> Color? {
        guard let value = rgb(hex) else { return nil }
        return Color(.sRGB, red: value.r, green: value.g, blue: value.b, opacity: 1)
    }

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let number = UInt32(text, radix: 16) else { return nil }
        return (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
    }

    static func string(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
}
