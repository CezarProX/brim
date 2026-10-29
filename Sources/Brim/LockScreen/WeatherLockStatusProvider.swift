import SwiftUI

/// Adds the current temperature to the lock-screen status row when Weather is on and has data.
struct WeatherLockStatusProvider: LockStatusProvider {
    let id = "weather"
    var snapshot: @MainActor () -> WeatherSnapshot? = { WeatherStore.shared.snapshot }

    @MainActor
    func items(now: Date) -> [LockStatusItem] {
        guard AppSettings.shared.weatherEnabled, let snapshot = snapshot() else { return [] }
        let unit = AppSettings.shared.weatherUnit
        return [LockStatusItem(
            id: id, symbol: snapshot.symbol, title: unit.format(celsius: snapshot.celsius),
            detail: snapshot.condition.label, tint: .white)]
    }
}
