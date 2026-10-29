import Foundation
import SwiftUI

/// One tile in the row under the lock-screen clock.
struct LockStatusItem: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
}

/// Anything that can contribute tiles to the status row. Weather and other providers register here
/// without the lock-screen code knowing about them.
@MainActor
protocol LockStatusProvider {
    var id: String { get }
    func items(now: Date) -> [LockStatusItem]
}

@MainActor
final class LockStatusRegistry {
    static let shared = LockStatusRegistry(providers: [BatteryStatusProvider(), CalendarStatusProvider()])
    private(set) var providers: [any LockStatusProvider]
    /// Tiles beyond this many are dropped; the row is a glance, not a list.
    static let maxItems = 4

    init(providers: [any LockStatusProvider]) { self.providers = providers }

    func register(_ provider: any LockStatusProvider) {
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
    }

    func items(now: Date = .now) -> [LockStatusItem] {
        Array(providers.flatMap { $0.items(now: now) }.prefix(Self.maxItems))
    }
}

struct BatteryStatusProvider: LockStatusProvider {
    let id = "battery"
    var reader: @Sendable () -> PowerFlashRules.Reading? = { SystemSignalsMonitor.readPower() }

    func items(now: Date) -> [LockStatusItem] {
        guard let reading = reader() else { return [] }
        let low = reading.percent <= 20 && !reading.externalPower
        let symbol = reading.externalPower ? "battery.100percent.bolt" : Self.symbol(for: reading.percent)
        return [LockStatusItem(
            id: id, symbol: symbol, title: "\(reading.percent)%",
            detail: reading.externalPower ? "Charging" : "Battery",
            tint: low ? .red : (reading.externalPower ? .green : .white))]
    }

    static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct CalendarStatusProvider: LockStatusProvider {
    let id = "calendar"
    var meeting: @MainActor () -> CalendarMeeting? = { CalendarActivityModel.shared.meeting }

    func items(now: Date) -> [LockStatusItem] {
        guard let event = meeting(), event.endsAt > now else { return [] }
        let live = event.startsAt <= now
        return [LockStatusItem(
            id: id, symbol: "calendar", title: String(event.title.prefix(22)),
            detail: live ? "Now" : event.startsAt.formatted(date: .omitted, time: .shortened),
            tint: Color(red: 1, green: 0.27, blue: 0.23))]
    }
}
