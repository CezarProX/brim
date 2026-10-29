// SkyExtras.swift
// Brim
//
// Sunrise / sunset and air quality from Open-Meteo (HTTPS, no key). Pure parts only: URL builders,
// decoding and the rules that pick what a lock-screen chip shows.

import Foundation
import SwiftUI

struct SkyExtras: Equatable, Sendable {
  var sunrises: [Date] = []
  var sunsets: [Date] = []
  var usAQI: Int?
  var fetchedAt: Date = .distantPast
}

struct SunEvent: Equatable {
  let isSunrise: Bool
  let date: Date
}

struct AQICategory: Equatable {
  let label: String
  let color: Color

  /// US EPA bands.
  static func make(_ aqi: Int) -> AQICategory {
    switch aqi {
    case ..<51: return AQICategory(label: "Good", color: .green)
    case 51..<101: return AQICategory(label: "Moderate", color: .yellow)
    case 101..<151: return AQICategory(label: "Sensitive groups", color: .orange)
    case 151..<201: return AQICategory(label: "Unhealthy", color: .red)
    case 201..<301: return AQICategory(label: "Very unhealthy", color: .purple)
    default: return AQICategory(label: "Hazardous", color: Color(red: 0.6, green: 0.1, blue: 0.2))
    }
  }
}

enum SkyRules {
  /// The next sunrise or sunset strictly after `now`.
  static func nextSunEvent(now: Date, sunrises: [Date], sunsets: [Date]) -> SunEvent? {
    let rises = sunrises.filter { $0 > now }.map { SunEvent(isSunrise: true, date: $0) }
    let sets = sunsets.filter { $0 > now }.map { SunEvent(isSunrise: false, date: $0) }
    return (rises + sets).min { $0.date < $1.date }
  }

  /// Data older than this is not shown on the lock screen.
  static func isFresh(_ extras: SkyExtras, now: Date, maxAge: TimeInterval = 3 * 3600) -> Bool {
    now.timeIntervalSince(extras.fetchedAt) < maxAge
  }

  static func decodeSun(_ data: Data) -> (sunrises: [Date], sunsets: [Date])? {
    struct Response: Decodable {
      struct Daily: Decodable { let sunrise: [Double?]; let sunset: [Double?] }
      let daily: Daily
    }
    guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
    func dates(_ values: [Double?]) -> [Date] { values.compactMap { $0 }.map { Date(timeIntervalSince1970: $0) } }
    return (dates(response.daily.sunrise), dates(response.daily.sunset))
  }

  static func decodeAQI(_ data: Data) -> Int? {
    struct Response: Decodable {
      struct Current: Decodable { let us_aqi: Double? }
      let current: Current
    }
    guard let value = (try? JSONDecoder().decode(Response.self, from: data))?.current.us_aqi,
          value.isFinite, value >= 0 else { return nil }
    return Int(value.rounded())
  }

  static func sunURL(latitude: Double, longitude: Double) -> URL? {
    build(host: "api.open-meteo.com", path: "/v1/forecast", latitude: latitude, longitude: longitude, extra: [
      URLQueryItem(name: "daily", value: "sunrise,sunset"),
      URLQueryItem(name: "timeformat", value: "unixtime"),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "2"),
    ])
  }

  static func airQualityURL(latitude: Double, longitude: Double) -> URL? {
    build(host: "air-quality-api.open-meteo.com", path: "/v1/air-quality", latitude: latitude, longitude: longitude, extra: [
      URLQueryItem(name: "current", value: "us_aqi"),
    ])
  }

  private static func build(
    host: String, path: String, latitude: Double, longitude: Double, extra: [URLQueryItem]
  ) -> URL? {
    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = host
    parts.path = path
    parts.queryItems = [
      URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
      URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
    ] + extra
    return parts.url
  }
}
