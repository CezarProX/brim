import Foundation
import SwiftUI

/// What the sky is doing, grouped from WMO weather codes (the codes Open-Meteo reports).
enum WeatherCondition: Equatable, Sendable {
  case clear, mostlyClear, partlyCloudy, overcast, fog
  case drizzle, freezingDrizzle, lightRain, rain, heavyRain, freezingRain
  case lightSnow, snow, heavySnow, snowGrains
  case rainShowers, heavyShowers, snowShowers
  case thunderstorm, thunderstormHail
  case unknown

  init(code: Int) {
    switch code {
    case 0: self = .clear
    case 1: self = .mostlyClear
    case 2: self = .partlyCloudy
    case 3: self = .overcast
    case 45, 48: self = .fog
    case 51, 53, 55: self = .drizzle
    case 56, 57: self = .freezingDrizzle
    case 61: self = .lightRain
    case 63: self = .rain
    case 65: self = .heavyRain
    case 66, 67: self = .freezingRain
    case 71: self = .lightSnow
    case 73: self = .snow
    case 75: self = .heavySnow
    case 77: self = .snowGrains
    case 80, 81: self = .rainShowers
    case 82: self = .heavyShowers
    case 85, 86: self = .snowShowers
    case 95: self = .thunderstorm
    case 96, 99: self = .thunderstormHail
    default: self = .unknown
    }
  }

  var label: String {
    switch self {
    case .clear: "Clear"
    case .mostlyClear: "Mostly clear"
    case .partlyCloudy: "Partly cloudy"
    case .overcast: "Overcast"
    case .fog: "Fog"
    case .drizzle: "Drizzle"
    case .freezingDrizzle: "Freezing drizzle"
    case .lightRain: "Light rain"
    case .rain: "Rain"
    case .heavyRain: "Heavy rain"
    case .freezingRain: "Freezing rain"
    case .lightSnow: "Light snow"
    case .snow: "Snow"
    case .heavySnow: "Heavy snow"
    case .snowGrains: "Snow grains"
    case .rainShowers: "Rain showers"
    case .heavyShowers: "Heavy showers"
    case .snowShowers: "Snow showers"
    case .thunderstorm: "Thunderstorm"
    case .thunderstormHail: "Thunderstorm, hail"
    case .unknown: "Unknown"
    }
  }

  /// SF Symbol (multicolor-friendly "fill" variants), with moon variants after dark.
  func symbol(isNight: Bool) -> String {
    switch self {
    case .clear: return isNight ? "moon.stars.fill" : "sun.max.fill"
    case .mostlyClear: return isNight ? "moon.fill" : "sun.min.fill"
    case .partlyCloudy: return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
    case .overcast: return "cloud.fill"
    case .fog: return "cloud.fog.fill"
    case .drizzle: return "cloud.drizzle.fill"
    case .freezingDrizzle, .freezingRain: return "cloud.sleet.fill"
    case .lightRain, .rain: return "cloud.rain.fill"
    case .heavyRain: return "cloud.heavyrain.fill"
    case .lightSnow, .snow, .heavySnow, .snowShowers: return "cloud.snow.fill"
    case .snowGrains: return "snowflake"
    case .rainShowers: return isNight ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
    case .heavyShowers: return "cloud.heavyrain.fill"
    case .thunderstorm, .thunderstormHail: return "cloud.bolt.rain.fill"
    case .unknown: return "questionmark.circle"
    }
  }

  var isWet: Bool {
    switch self {
    case .drizzle, .freezingDrizzle, .lightRain, .rain, .heavyRain, .freezingRain, .rainShowers,
      .heavyShowers, .thunderstorm, .thunderstormHail:
      return true
    default: return false
    }
  }

  /// Top and bottom colors of the widget card: sky by condition, darker after dark.
  func gradient(isNight: Bool) -> [Color] {
    func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    switch self {
    case .clear, .mostlyClear:
      return isNight ? [rgb(18, 24, 66), rgb(52, 44, 110)] : [rgb(58, 142, 240), rgb(112, 189, 250)]
    case .partlyCloudy:
      return isNight ? [rgb(30, 38, 78), rgb(66, 72, 112)] : [rgb(72, 132, 206), rgb(138, 176, 218)]
    case .overcast, .fog:
      return isNight ? [rgb(40, 44, 54), rgb(70, 74, 86)] : [rgb(102, 118, 138), rgb(150, 162, 176)]
    case .drizzle, .freezingDrizzle, .lightRain, .rain, .rainShowers:
      return isNight ? [rgb(26, 34, 56), rgb(52, 66, 92)] : [rgb(62, 84, 116), rgb(100, 124, 152)]
    case .heavyRain, .heavyShowers, .freezingRain:
      return isNight ? [rgb(20, 26, 44), rgb(42, 54, 78)] : [rgb(48, 64, 92), rgb(84, 102, 130)]
    case .lightSnow, .snow, .heavySnow, .snowGrains, .snowShowers:
      return isNight ? [rgb(50, 62, 92), rgb(96, 112, 142)] : [rgb(128, 158, 196), rgb(194, 212, 232)]
    case .thunderstorm, .thunderstormHail:
      return isNight ? [rgb(26, 22, 48), rgb(54, 44, 82)] : [rgb(60, 56, 96), rgb(98, 90, 130)]
    case .unknown:
      return [rgb(70, 80, 100), rgb(110, 120, 140)]
    }
  }
}

// MARK: - Units

extension WeatherUnit {
  /// Resolves Automatic from the user's region: Fahrenheit for the US, Celsius elsewhere.
  func resolved(locale: Locale = .current) -> WeatherUnit {
    guard self == .automatic else { return self }
    return locale.measurementSystem == .us ? .fahrenheit : .celsius
  }

  func convert(celsius: Double, locale: Locale = .current) -> Double {
    resolved(locale: locale) == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
  }

  /// "72°" — rounded, no unit letter, as in the system Weather app.
  func format(celsius: Double, locale: Locale = .current) -> String {
    let value = Int(convert(celsius: celsius, locale: locale).rounded())
    return "\(value == 0 ? 0 : value)°"
  }
}

// MARK: - Forecast

struct WeatherHour: Codable, Equatable, Identifiable, Sendable {
  var id: Date { date }
  let date: Date
  let celsius: Double
  let code: Int
  let isDay: Bool
}

struct WeatherDay: Codable, Equatable, Identifiable, Sendable {
  var id: Date { date }
  let date: Date
  let code: Int
  let highCelsius: Double
  let lowCelsius: Double
  /// Chance of precipitation, 0...100, where the service reports one.
  let rainPercent: Int?
}

/// Everything the widget draws, normalised to Celsius and unix dates. Cached as JSON.
struct WeatherSnapshot: Codable, Equatable, Sendable {
  let place: String
  let fetched: Date
  let celsius: Double
  let feelsLikeCelsius: Double?
  let code: Int
  let isDay: Bool
  let highCelsius: Double
  let lowCelsius: Double
  let hours: [WeatherHour]
  /// Today and the days after it; nil for forecasts cached before the daily outlook existed.
  var days: [WeatherDay]?
  var humidityPercent: Int?
  var windKmh: Double?

  var condition: WeatherCondition { WeatherCondition(code: code) }
  var symbol: String { condition.symbol(isNight: !isDay) }
}

enum WeatherError: Error, Equatable, LocalizedError {
  case badResponse
  case missingData
  case noLocation

  var errorDescription: String? {
    switch self {
    case .badResponse: "The weather service didn’t answer."
    case .missingData: "The weather service sent incomplete data."
    case .noLocation: "Choose a city, or use your Mac’s location."
    }
  }
}

/// The Open-Meteo `forecast` JSON we ask for (`timeformat=unixtime`, Celsius).
struct OpenMeteoResponse: Decodable, Sendable {
  struct Current: Decodable, Sendable {
    let time: Double
    let temperature_2m: Double
    let apparent_temperature: Double?
    let weather_code: Int
    let is_day: Int
    let relative_humidity_2m: Double?
    let wind_speed_10m: Double?
  }
  struct Hourly: Decodable, Sendable {
    let time: [Double]
    let temperature_2m: [Double?]
    let weather_code: [Int?]
    let is_day: [Int?]
  }
  struct Daily: Decodable, Sendable {
    let time: [Double]?
    let weather_code: [Int?]?
    let precipitation_probability_max: [Int?]?
    let temperature_2m_max: [Double?]
    let temperature_2m_min: [Double?]
  }
  let current: Current
  let hourly: Hourly
  let daily: Daily

  /// One entry per forecast day; days with a missing value are skipped.
  private func outlook() -> [WeatherDay]? {
    guard let times = daily.time, !times.isEmpty else { return nil }
    var days: [WeatherDay] = []
    for (index, time) in times.enumerated() {
      guard index < daily.temperature_2m_max.count, let high = daily.temperature_2m_max[index],
        index < daily.temperature_2m_min.count, let low = daily.temperature_2m_min[index]
      else { continue }
      let code = (daily.weather_code.flatMap { index < $0.count ? $0[index] : nil }) ?? 0
      let rain = daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil }
      days.append(
        WeatherDay(
          date: Date(timeIntervalSince1970: time), code: code, highCelsius: high, lowCelsius: low, rainPercent: rain))
    }
    return days.isEmpty ? nil : days
  }

  /// Builds the snapshot: the next `hourCount` hours from the current one, plus today's range.
  func snapshot(place: String, now: Date, hourCount: Int = 12) throws -> WeatherSnapshot {
    guard let high = daily.temperature_2m_max.first.flatMap({ $0 }),
      let low = daily.temperature_2m_min.first.flatMap({ $0 })
    else { throw WeatherError.missingData }
    let start = now.timeIntervalSince1970 - 1800
    var hours: [WeatherHour] = []
    for (index, time) in hourly.time.enumerated() where time >= start {
      guard index < hourly.temperature_2m.count, let celsius = hourly.temperature_2m[index],
        index < hourly.weather_code.count, let code = hourly.weather_code[index]
      else { continue }
      let day = index < hourly.is_day.count ? (hourly.is_day[index] ?? 1) : 1
      hours.append(WeatherHour(date: Date(timeIntervalSince1970: time), celsius: celsius, code: code, isDay: day == 1))
      if hours.count == hourCount { break }
    }
    return WeatherSnapshot(
      place: place, fetched: now, celsius: current.temperature_2m,
      feelsLikeCelsius: current.apparent_temperature, code: current.weather_code,
      isDay: current.is_day == 1, highCelsius: high, lowCelsius: low, hours: hours,
      days: outlook(), humidityPercent: current.relative_humidity_2m.map { Int($0.rounded()) },
      windKmh: current.wind_speed_10m)
  }
}

struct GeocodingResponse: Decodable, Sendable {
  struct Place: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var subtitle: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
  }
  let results: [Place]?
}
