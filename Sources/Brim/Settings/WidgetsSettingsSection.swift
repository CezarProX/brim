// WidgetsSettingsSection.swift
// Brim
//
// Settings for Home widgets, island glances, Weather and System Stats.

import SwiftUI

struct WidgetsSettingsSection: View {
  /// Which groups to show: Home & glances on the Home & Widgets page, Weather and Stats as tools.
  enum Part: CaseIterable { case home, weather, stats }
  var parts: Set<Part> = Set(Part.allCases)

  @State private var scrollMode = AppSettings.shared.widgetScrollMode
  @State private var leftGlance = IslandGlanceModel.shared.left
  @State private var rightGlance = IslandGlanceModel.shared.right
  @State private var leftGlanceSecond = IslandGlanceModel.shared.leftSecond
  @State private var rightGlanceSecond = IslandGlanceModel.shared.rightSecond
  @State private var leftCard = AppSettings.shared.statsLeftCard
  @State private var rightCard = AppSettings.shared.statsRightCard
  @State private var sampleSeconds = AppSettings.shared.statsSampleSeconds
  @State private var alertCPU = AppSettings.shared.statsAlertCPU
  @State private var alertMemory = AppSettings.shared.statsAlertMemory
  @State private var alertTemperature = AppSettings.shared.statsAlertTemperature
  @State private var alertDisk = AppSettings.shared.statsAlertDisk

  var body: some View {
    Group {
      if parts.contains(.home) {
      SettingsSection(
        "Home widgets",
        footer: "Use Customize Home in the island’s ••• menu to add up to six widgets and drag them into order. Automatic scrolls sideways."
      ) {
        Picker("When there are more than three widgets", selection: $scrollMode) {
          ForEach(WidgetScrollMode.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: scrollMode) { _, value in AppSettings.shared.widgetScrollMode = value }
      }
      SettingsSection(
        "Island glances",
        footer: "A glance is a small readout beside the closed island; each side holds two. The timer glance appears only while a timer runs, and Next event shows your next meeting once Calendar is connected."
      ) {
        Picker("Left of the island", selection: $leftGlance) {
          ForEach(IslandGlance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .onChange(of: leftGlance) { _, value in IslandGlanceModel.shared.set(value, for: .left) }
        Picker("Right of the island", selection: $rightGlance) {
          ForEach(IslandGlance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .onChange(of: rightGlance) { _, value in IslandGlanceModel.shared.set(value, for: .right) }
        Picker("Left, second glance", selection: $leftGlanceSecond) {
          ForEach(IslandGlance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .onChange(of: leftGlanceSecond) { _, value in IslandGlanceModel.shared.set(value, for: .left, second: true) }
        Picker("Right, second glance", selection: $rightGlanceSecond) {
          ForEach(IslandGlance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .onChange(of: rightGlanceSecond) { _, value in IslandGlanceModel.shared.set(value, for: .right, second: true) }
      }
      }
      if parts.contains(.weather) { WeatherSettingsCard() }
      if parts.contains(.stats) {
      SettingsSection("System Stats") {
        Picker("Left card", selection: $leftCard) { ForEach(StatsCard.allCases) { Text($0.title).tag($0) } }
          .onChange(of: leftCard) { _, value in AppSettings.shared.statsLeftCard = value }
        Picker("Right card", selection: $rightCard) { ForEach(StatsCard.allCases) { Text($0.title).tag($0) } }
          .onChange(of: rightCard) { _, value in AppSettings.shared.statsRightCard = value }
        Stepper("Sample every \(sampleSeconds) s", value: $sampleSeconds, in: 1...10)
          .onChange(of: sampleSeconds) { _, value in
            AppSettings.shared.statsSampleSeconds = value
            SystemStatsModel.shared.intervalChanged()
          }
      }
      SettingsSection(
        "Alerts flash in the island",
        footer: "Each alert shows at most once every ten minutes. Everything is measured on this Mac."
      ) {
        alertToggle("High CPU (above 90% for 10 seconds)", $alertCPU) { AppSettings.shared.statsAlertCPU = $0 }
        alertToggle("Memory pressure", $alertMemory) { AppSettings.shared.statsAlertMemory = $0 }
        alertToggle("High temperature (macOS thermal state)", $alertTemperature) { AppSettings.shared.statsAlertTemperature = $0 }
        alertToggle("Low disk space (under 10 GB)", $alertDisk) { AppSettings.shared.statsAlertDisk = $0 }
      }
      }
    }
  }

  private func alertToggle(_ title: String, _ binding: Binding<Bool>, apply: @escaping (Bool) -> Void) -> some View {
    Toggle(title, isOn: binding).onChange(of: binding.wrappedValue) { _, value in
      apply(value)
      StatsAlertMonitor.shared.settingsChanged()
    }
  }
}

/// Weather: opt-in, because it contacts open-meteo.com.
private struct WeatherSettingsCard: View {
  @State private var enabled = AppSettings.shared.weatherEnabled
  @State private var mode = AppSettings.shared.weatherLocationMode
  @State private var unit = AppSettings.shared.weatherUnit
  @State private var minutes = AppSettings.shared.weatherRefreshMinutes
  @State private var city = AppSettings.shared.weatherCityName
  @State private var query = ""
  @State private var results: [GeocodingResponse.Place] = []
  @State private var searching = false
  @State private var searchFailed = false

  var body: some View {
    SettingsSection("Weather") {
      Toggle(isOn: $enabled) {
        Text("Show weather")
        Text("Off by default. When on, Brim sends the chosen coordinates (and nothing else) to open-meteo.com over HTTPS. There is no account or API key.")
      }
      .settingsAnchor("weather.enable")
        .onChange(of: enabled) { _, value in
          AppSettings.shared.weatherEnabled = value
          WeatherStore.shared.settingsChanged()
        }
      if enabled {
        Picker("Location", selection: $mode) {
          ForEach(WeatherLocationMode.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: mode) { _, value in
          AppSettings.shared.weatherLocationMode = value
          WeatherStore.shared.settingsChanged()
        }
        .settingsAnchor("weather.location")
        if mode == .custom { citySearch.settingsAnchor("weather.city") } else {
          SettingsFootnote("macOS asks for location access the first time. Only an approximate position is requested.")
        }
        Picker("Temperature", selection: $unit) { ForEach(WeatherUnit.allCases) { Text($0.title).tag($0) } }
          .onChange(of: unit) { _, value in
            AppSettings.shared.weatherUnit = value
            WeatherStore.shared.objectWillChange.send()
          }
        Stepper("Refresh every \(minutes) min", value: $minutes, in: 5...180, step: 5)
          .onChange(of: minutes) { _, value in
            AppSettings.shared.weatherRefreshMinutes = value
            WeatherStore.shared.settingsChanged()
          }
      }
    }
  }

  private var citySearch: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TextField(city.isEmpty ? "Search for a city" : city, text: $query)
          .textFieldStyle(.roundedBorder).onSubmit(search)
        Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || searching)
      }
      if !city.isEmpty { Label(city, systemImage: "mappin.circle.fill").font(.caption).foregroundStyle(.secondary) }
      if searchFailed { SettingsFootnote("Couldn’t reach the search service. Check your connection and try again.") }
      ForEach(results) { place in
        Button { choose(place) } label: {
          HStack {
            Text(place.name).fontWeight(.medium)
            Text(place.subtitle).foregroundStyle(.secondary)
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func search() {
    let text = query
    searching = true
    searchFailed = false
    Task {
      do { results = try await WeatherService().search(text) } catch {
        results = []
        searchFailed = true
      }
      searching = false
    }
  }

  private func choose(_ place: GeocodingResponse.Place) {
    let settings = AppSettings.shared
    settings.weatherCityName = place.name
    settings.weatherLatitude = place.latitude
    settings.weatherLongitude = place.longitude
    city = place.name
    results = []
    query = ""
    WeatherStore.shared.settingsChanged()
  }
}
