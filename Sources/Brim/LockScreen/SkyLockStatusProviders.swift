// SkyLockStatusProviders.swift
// Brim
//
// Lock-screen chips for the next sunrise / sunset and the local air quality. Both are opt-in and
// stay empty until the Weather location is known and a fetch has succeeded.

import SwiftUI

struct SunLockStatusProvider: LockStatusProvider {
    let id = "sun"
    var extras: @MainActor () -> SkyExtras? = { SkyExtrasStore.shared.extras }

    @MainActor
    func items(now: Date) -> [LockStatusItem] {
        guard AppSettings.shared.lockSunChipEnabled, let data = extras(), SkyRules.isFresh(data, now: now),
              let event = SkyRules.nextSunEvent(now: now, sunrises: data.sunrises, sunsets: data.sunsets)
        else { return [] }
        return [LockStatusItem(
            id: id, symbol: event.isSunrise ? "sunrise.fill" : "sunset.fill",
            title: event.date.formatted(date: .omitted, time: .shortened),
            detail: event.isSunrise ? "Sunrise" : "Sunset", tint: .orange)]
    }
}

struct AirQualityLockStatusProvider: LockStatusProvider {
    let id = "air"
    var extras: @MainActor () -> SkyExtras? = { SkyExtrasStore.shared.extras }

    @MainActor
    func items(now: Date) -> [LockStatusItem] {
        guard AppSettings.shared.lockAirQualityChipEnabled, let data = extras(),
              SkyRules.isFresh(data, now: now), let aqi = data.usAQI else { return [] }
        let category = AQICategory.make(aqi)
        return [LockStatusItem(
            id: id, symbol: "aqi.medium", title: "AQI \(aqi)", detail: category.label, tint: category.color)]
    }
}
