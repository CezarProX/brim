import CoreGraphics
import Foundation

/// Which displays a compact HUD appears on. The shell asks for the screen ids and shows the HUD on
/// each; "under pointer" falls back to the main display when the pointer is between displays.
enum HUDDisplayPolicy {
    struct Display: Equatable {
        let id: Int
        let frame: CGRect
        let isMain: Bool
    }

    static func targets(_ target: HUDDisplayTarget, pointer: CGPoint, displays: [Display]) -> [Int] {
        guard !displays.isEmpty else { return [] }
        let main = displays.first(where: \.isMain) ?? displays[0]
        switch target {
        case .mainDisplay: return [main.id]
        case .allDisplays: return displays.map(\.id)
        case .underPointer:
            return [displays.first(where: { $0.frame.contains(pointer) })?.id ?? main.id]
        }
    }

    /// Whether a HUD hosted on `displayID` should be drawn.
    static func shows(on displayID: Int, target: HUDDisplayTarget, pointer: CGPoint, displays: [Display]) -> Bool {
        targets(target, pointer: pointer, displays: displays).contains(displayID)
    }
}

import AppKit

extension HUDDisplayPolicy {
    /// The connected screens as policy input; `id` is the CGDirectDisplayID.
    @MainActor
    static func liveDisplays() -> [Display] {
        let main = NSScreen.screens.first
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return Display(id: number.intValue, frame: screen.frame, isMain: screen == main)
        }
    }
}
