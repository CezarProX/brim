import Foundation

/// Open-Meteo client: HTTPS only, no API key, short timeouts, nothing stored but the result.
struct WeatherService: Sendable {
  var session: URLSession = WeatherService.makeSession()

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }

  static func forecastURL(latitude: Double, longitude: Double) -> URL? {
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = "api.open-meteo.com"
    parts.path = "/v1/forecast"
    parts.queryItems = [
      URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
      URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
      URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
      URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
      URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
      URLQueryItem(name: "timeformat", value: "unixtime"),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "5"),
    ]
    return parts.url
  }

  static func geocodingURL(query: String) -> URL? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else { return nil }
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = "geocoding-api.open-meteo.com"
    parts.path = "/v1/search"
    parts.queryItems = [
      URLQueryItem(name: "name", value: String(trimmed.prefix(80))),
      URLQueryItem(name: "count", value: "6"),
      URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
      URLQueryItem(name: "format", value: "json"),
    ]
    return parts.url
  }

  func forecast(latitude: Double, longitude: Double, place: String, now: Date = .now) async throws
    -> WeatherSnapshot
  {
    guard (-90...90).contains(latitude), (-180...180).contains(longitude),
      let url = Self.forecastURL(latitude: latitude, longitude: longitude)
    else { throw WeatherError.noLocation }
    let data = try await load(url)
    let response: OpenMeteoResponse
    do { response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data) } catch {
      throw WeatherError.missingData
    }
    return try response.snapshot(place: place, now: now)
  }

  func search(_ query: String) async throws -> [GeocodingResponse.Place] {
    guard let url = Self.geocodingURL(query: query) else { return [] }
    let data = try await load(url)
    return try JSONDecoder().decode(GeocodingResponse.self, from: data).results ?? []
  }

  private func load(_ url: URL) async throws -> Data {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 1_000_000 else {
      throw WeatherError.badResponse
    }
    return data
  }
}
