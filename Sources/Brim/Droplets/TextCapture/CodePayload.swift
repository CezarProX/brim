// CodePayload.swift
// Brim
//
// Turns a scanned QR / barcode string into something the user can act on. Only http(s), mailto,
// tel, sms and map links are ever offered to open; any other scheme is shown as text.

import Foundation

struct CodePayload: Equatable {
  enum Kind: String, Equatable {
    case url, wifi, email, phone, sms, location, contact, event, authenticator, product, text
  }

  let kind: Kind
  let title: String
  let detail: String
  /// A link the user can open, or nil.
  let openURL: URL?
  /// What "Copy" should put on the clipboard (the Wi-Fi password, the bare address ...).
  let copyValue: String
  var symbol: String {
    switch kind {
    case .url: "link"
    case .wifi: "wifi"
    case .email: "envelope.fill"
    case .phone: "phone.fill"
    case .sms: "message.fill"
    case .location: "mappin.and.ellipse"
    case .contact: "person.crop.circle.fill"
    case .event: "calendar"
    case .authenticator: "lock.shield.fill"
    case .product: "barcode"
    case .text: "text.alignleft"
    }
  }

  static func classify(_ raw: String, symbology: String = "QR code") -> CodePayload {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    if lower.hasPrefix("wifi:") { return wifi(text) }
    if lower.hasPrefix("mailto:") { return email(text) }
    if lower.hasPrefix("tel:") { return phone(text) }
    if lower.hasPrefix("smsto:") || lower.hasPrefix("sms:") { return sms(text) }
    if lower.hasPrefix("geo:") { return geo(text) }
    if lower.hasPrefix("begin:vcard") || lower.hasPrefix("mecard:") { return contact(text) }
    if lower.hasPrefix("begin:vevent") || lower.hasPrefix("begin:vcalendar") { return event(text) }
    if lower.hasPrefix("otpauth://") {
      return CodePayload(kind: .authenticator, title: "Authenticator secret", detail: "Keep this private", openURL: nil, copyValue: text)
    }
    if let url = webURL(text) {
      return CodePayload(kind: .url, title: "Link", detail: url.host ?? text, openURL: url, copyValue: text)
    }
    if symbology != "QR code", text.allSatisfy(\.isNumber) {
      return CodePayload(kind: .product, title: "\(symbology) barcode", detail: text, openURL: nil, copyValue: text)
    }
    return CodePayload(kind: .text, title: "Text", detail: String(text.prefix(120)), openURL: nil, copyValue: text)
  }

  static func webURL(_ text: String) -> URL? {
    guard !text.contains(where: \.isWhitespace), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", url.host?.isEmpty == false
    else { return nil }
    return url
  }

  // MARK: Formats

  /// `WIFI:T:WPA;S:Home;P:secret;H:true;;` with `\;`, `\:`, `\,` and `\\` escapes.
  static func wifiFields(_ text: String) -> [String: String] {
    var fields: [String: String] = [:]
    var key = "", value = "", inValue = false, escaped = false
    for character in text.dropFirst(5) {
      if escaped {
        if inValue { value.append(character) } else { key.append(character) }
        escaped = false
        continue
      }
      switch character {
      case "\\": escaped = true
      case ":" where !inValue: inValue = true
      case ";":
        if !key.isEmpty { fields[key.uppercased()] = value }
        key = ""; value = ""; inValue = false
      default: if inValue { value.append(character) } else { key.append(character) }
      }
    }
    return fields
  }

  private static func wifi(_ text: String) -> CodePayload {
    let fields = wifiFields(text)
    let name = fields["S"] ?? "Wi-Fi network"
    let security = (fields["T"]?.isEmpty == false ? fields["T"]! : "none")
    let password = fields["P"] ?? ""
    let detail = password.isEmpty ? "\(security) · open network" : "\(security) · password copies"
    return CodePayload(kind: .wifi, title: "Wi-Fi: \(name)", detail: detail, openURL: nil, copyValue: password.isEmpty ? name : password)
  }

  private static func email(_ text: String) -> CodePayload {
    let address = String(text.dropFirst(7)).split(separator: "?").first.map(String.init) ?? ""
    let url = URL(string: text)
    return CodePayload(kind: .email, title: "Email", detail: address, openURL: url, copyValue: address)
  }

  private static func phone(_ text: String) -> CodePayload {
    let number = String(text.dropFirst(4))
    return CodePayload(kind: .phone, title: "Phone number", detail: number, openURL: URL(string: "tel:" + digitsOnly(number)), copyValue: number)
  }

  private static func sms(_ text: String) -> CodePayload {
    let rest = text.drop { $0 != ":" }.dropFirst()
    let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
    let number = parts.first ?? ""
    let body = parts.count > 1 ? parts[1] : ""
    return CodePayload(kind: .sms, title: "Text message", detail: body.isEmpty ? number : "\(number): \(body)",
                       openURL: URL(string: "sms:" + digitsOnly(number)), copyValue: body.isEmpty ? number : body)
  }

  private static func geo(_ text: String) -> CodePayload {
    let coords = text.dropFirst(4).split(separator: "?").first.map(String.init) ?? ""
    let parts = coords.split(separator: ",").prefix(2).map(String.init)
    let url = parts.count == 2 ? URL(string: "https://maps.apple.com/?ll=\(parts[0]),\(parts[1])") : nil
    return CodePayload(kind: .location, title: "Location", detail: parts.joined(separator: ", "), openURL: url, copyValue: coords)
  }

  private static func contact(_ text: String) -> CodePayload {
    var name = ""
    for line in text.split(whereSeparator: \.isNewline) {
      let upper = line.uppercased()
      if upper.hasPrefix("FN:") { name = String(line.dropFirst(3)); break }
      if upper.hasPrefix("N:") { name = String(line.dropFirst(2)).split(separator: ";").joined(separator: " ") }
    }
    if name.isEmpty, text.uppercased().hasPrefix("MECARD:") {
      name = text.dropFirst(7).components(separatedBy: ";").first { $0.uppercased().hasPrefix("N:") }.map { String($0.dropFirst(2)).replacingOccurrences(of: ",", with: " ") } ?? ""
    }
    return CodePayload(kind: .contact, title: "Contact", detail: name.isEmpty ? "Contact card" : name, openURL: nil, copyValue: text)
  }

  private static func event(_ text: String) -> CodePayload {
    let summary = text.split(whereSeparator: \.isNewline).first { $0.uppercased().hasPrefix("SUMMARY:") }.map { String($0.dropFirst(8)) } ?? "Calendar event"
    return CodePayload(kind: .event, title: "Calendar event", detail: summary, openURL: nil, copyValue: text)
  }

  private static func digitsOnly(_ text: String) -> String { text.filter { $0.isNumber || $0 == "+" } }
}
