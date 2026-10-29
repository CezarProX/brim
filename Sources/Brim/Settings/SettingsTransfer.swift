import Foundation

/// Export and import of Brim's preferences as JSON. Secrets, caches and system-owned keys never travel.
enum SettingsTransfer {
  static let format = "BrimSettings"
  /// Files exported before the app was renamed say "QuickShotSettings".
  static let acceptedFormats: Set<String> = [format, "QuickShotSettings"]
  static let version = 1
  /// Values bigger than this are caches or blobs, not preferences.
  static let maxDataBytes = 64 * 1024

  enum TransferError: Error, LocalizedError, Equatable {
    case notSettingsFile, newerVersion(Int), unreadable

    var errorDescription: String? {
      switch self {
      case .notSettingsFile: "This isn’t a Brim settings file."
      case .newerVersion(let v): "This file was made by a newer Brim (format \(v))."
      case .unreadable: "The file couldn’t be read."
      }
    }
  }

  struct ImportResult: Equatable {
    var applied: Int
    var skipped: [String]
  }

  // MARK: Key policy

  private static let blockedFragments = ["token", "secret", "password", "passwd", "apikey", "api_key", "credential", "license", "cache", "bookmark"]
  private static let blockedPrefixes = ["NS", "Apple", "AK", "com.apple.", "WebKit", "SU", "NavPanel", "ABDatabase", "PK", "FK", "INNext"]
  /// State that belongs to this Mac or this run, not to a preference set.
  private static let blockedExact: Set<String> = [
    "onboardingCompleted", "islandTourCompleted", "commandCenterLastPage", "launchAtLogin", "liquidPlayerOrigin",
  ]

  /// Settings that send screenshots off this Mac or point Brim at other code or servers. A settings
  /// file someone else hands you must not be able to set them; the user sets them in Settings.
  private static let importBlocked: Set<String> = [
    "autoUpload", "uploadServiceURL", "updateFeedURL", "agentStatusFile",
  ]

  static func isImportable(key: String) -> Bool { isExportable(key: key) && !importBlocked.contains(key) }

  static func isExportable(key: String) -> Bool {
    let lower = key.lowercased()
    if blockedExact.contains(key) { return false }
    if blockedPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
    return !blockedFragments.contains { lower.contains($0) }
  }

  // MARK: Export

  static func export(domain: [String: Any], appVersion: String, now: Date = .now) throws -> Data {
    var values: [String: Any] = [:]
    for (key, value) in domain where isExportable(key: key) {
      if let encoded = encode(value) { values[key] = encoded }
    }
    let envelope: [String: Any] = [
      "format": format, "version": version, "appVersion": appVersion,
      "exportedAt": ISO8601DateFormatter().string(from: now), "values": values,
    ]
    return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
  }

  // MARK: Import

  /// Applies the file's values to `defaults`. Blocked keys in a hand-edited file are skipped and reported.
  @discardableResult
  static func importSettings(_ data: Data, into defaults: UserDefaults) throws -> ImportResult {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw TransferError.unreadable }
    guard let fileFormat = root["format"] as? String, acceptedFormats.contains(fileFormat),
      let values = root["values"] as? [String: Any]
    else { throw TransferError.notSettingsFile }
    if let fileVersion = root["version"] as? Int, fileVersion > version { throw TransferError.newerVersion(fileVersion) }
    var result = ImportResult(applied: 0, skipped: [])
    for (key, raw) in values.sorted(by: { $0.key < $1.key }) {
      guard isImportable(key: key), let value = decode(raw) else { result.skipped.append(key); continue }
      defaults.set(value, forKey: key)
      result.applied += 1
    }
    return result
  }

  // MARK: Value coding (JSON has no Data or Date)

  private static func encode(_ value: Any) -> Any? {
    switch value {
    case let data as Data:
      return data.count <= maxDataBytes ? ["$data": data.base64EncodedString()] : nil
    case let date as Date: return ["$date": ISO8601DateFormatter().string(from: date)]
    case let string as String: return string
    case let number as NSNumber: return number
    case let array as [Any]:
      let items = array.compactMap(encode)
      return items.count == array.count ? items : nil
    case let dict as [String: Any]:
      var out: [String: Any] = [:]
      for (key, inner) in dict { guard let item = encode(inner) else { return nil }; out[key] = item }
      return out
    default: return nil
    }
  }

  private static func decode(_ raw: Any) -> Any? {
    switch raw {
    case let dict as [String: Any]:
      if dict.count == 1, let text = dict["$data"] as? String { return Data(base64Encoded: text) }
      if dict.count == 1, let text = dict["$date"] as? String { return ISO8601DateFormatter().date(from: text) }
      var out: [String: Any] = [:]
      for (key, inner) in dict { guard let item = decode(inner) else { return nil }; out[key] = item }
      return out
    case let array as [Any]:
      let items = array.compactMap(decode)
      return items.count == array.count ? items : nil
    case is NSNull: return nil
    default: return raw
    }
  }
}
