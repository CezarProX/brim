import Foundation

/// A small, safe arithmetic parser (no `NSExpression`, so odd input can never crash or run code).
/// Supports + - * / ^ %, parentheses, unary minus, `x% of y`, constants and common functions.
enum ThunderCalculator {
  /// The value of `text`, or nil when it is not a calculation. A bare number is not one.
  static func evaluate(_ text: String) -> Double? {
    let prepared = normalize(text)
    guard !prepared.isEmpty, prepared.count < 160, prepared.contains(where: \.isNumber) else { return nil }
    var parser = Parser(Array(prepared))
    guard let value = parser.parseExpression(), parser.atEnd, value.isFinite else { return nil }
    guard parser.usedOperatorOrFunction else { return nil }
    return value
  }

  /// Human formatting: up to 10 significant decimals, thousands separators, no trailing zeros.
  static func format(_ value: Double, locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) ? 0 : 10
    formatter.usesGroupingSeparator = true
    if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) {
      return String(format: "%.6g", value)
    }
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private static func normalize(_ text: String) -> String {
    var s = text.lowercased()
      .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
      .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: " ", with: "")
    // "20%of150" -> "(20/100*150)", anywhere in the expression.
    s = s.replacingOccurrences(
      of: #"(\d+(?:\.\d+)?)%of(\d+(?:\.\d+)?|\([^()]*\))"#, with: "($1/100*$2)", options: .regularExpression)
    return s
  }

  private struct Parser {
    let chars: [Character]
    var position = 0
    var usedOperatorOrFunction = false
    var depth = 0
    init(_ chars: [Character]) { self.chars = chars }
    var atEnd: Bool { position >= chars.count }
    var peek: Character? { atEnd ? nil : chars[position] }

    mutating func parseExpression() -> Double? {
      guard var value = parseTerm() else { return nil }
      while let c = peek, c == "+" || c == "-" {
        position += 1
        usedOperatorOrFunction = true
        guard let rhs = parseTerm() else { return nil }
        value = c == "+" ? value + rhs : value - rhs
      }
      return value
    }

    mutating func parseTerm() -> Double? {
      guard var value = parsePower() else { return nil }
      while let c = peek, c == "*" || c == "/" {
        position += 1
        usedOperatorOrFunction = true
        guard let rhs = parsePower() else { return nil }
        if c == "/" && rhs == 0 { return nil }
        value = c == "*" ? value * rhs : value / rhs
      }
      return value
    }

    mutating func parsePower() -> Double? {
      guard let base = parseUnary() else { return nil }
      if peek == "^" {
        position += 1
        usedOperatorOrFunction = true
        guard let exponent = parsePower() else { return nil }  // right associative
        let result = pow(base, exponent)
        return result.isFinite ? result : nil
      }
      return base
    }

    mutating func parseUnary() -> Double? {
      if peek == "-" { position += 1; usedOperatorOrFunction = true; return parseUnary().map { -$0 } }
      if peek == "+" { position += 1; return parseUnary() }
      guard var value = parsePrimary() else { return nil }
      while peek == "%" {
        // Postfix percent, unless it is followed by an operand (then it is not valid here).
        position += 1
        usedOperatorOrFunction = true
        value /= 100
      }
      return value
    }

    mutating func parsePrimary() -> Double? {
      guard let c = peek else { return nil }
      if c == "(" {
        depth += 1
        defer { depth -= 1 }
        guard depth < 40 else { return nil }
        position += 1
        guard let value = parseExpression(), peek == ")" else { return nil }
        position += 1
        return value
      }
      if c.isNumber || c == "." { return parseNumber() }
      if c.isLetter { return parseName() }
      return nil
    }

    mutating func parseNumber() -> Double? {
      let start = position
      while let c = peek, c.isNumber || c == "." { position += 1 }
      if let c = peek, c == "e", position + 1 < chars.count, chars[position + 1].isNumber || chars[position + 1] == "-" {
        position += 1
        if peek == "-" { position += 1 }
        while let d = peek, d.isNumber { position += 1 }
      }
      return Double(String(chars[start..<position]))
    }

    mutating func parseName() -> Double? {
      let start = position
      while let c = peek, c.isLetter { position += 1 }
      let name = String(chars[start..<position])
      switch name {
      case "pi", "π": return Double.pi
      case "e": return M_E
      default: break
      }
      guard peek == "(" else { return nil }
      usedOperatorOrFunction = true
      position += 1
      guard let argument = parseExpression(), peek == ")" else { return nil }
      position += 1
      return Self.apply(name, argument)
    }

    static func apply(_ name: String, _ x: Double) -> Double? {
      let value: Double
      switch name {
      case "sqrt": guard x >= 0 else { return nil }; value = sqrt(x)
      case "sin": value = sin(x)
      case "cos": value = cos(x)
      case "tan": value = tan(x)
      case "ln": guard x > 0 else { return nil }; value = log(x)
      case "log": guard x > 0 else { return nil }; value = log10(x)
      case "abs": value = abs(x)
      case "round": value = x.rounded()
      case "floor": value = floor(x)
      case "ceil": value = ceil(x)
      default: return nil
      }
      return value.isFinite ? value : nil
    }
  }
}

// MARK: - Unit conversion

struct ThunderConversion: Equatable {
  let value: Double
  let from: String
  let to: String
  let result: Double

  var display: String { "\(ThunderCalculator.format(result)) \(to)" }
}

enum ThunderUnits {
  private enum Dimension { case length, mass, volume, time, data, speed, temperature }
  private struct Unit { let names: [String]; let factor: Double; let dimension: Dimension; let label: String }

  /// factor = how many base units (m, kg, l, s, byte, m/s) one of this unit is.
  private static let units: [Unit] = [
    Unit(names: ["m", "meter", "meters", "metre", "metres"], factor: 1, dimension: .length, label: "m"),
    Unit(names: ["km", "kilometer", "kilometers", "kilometre", "kilometres"], factor: 1000, dimension: .length, label: "km"),
    Unit(names: ["cm", "centimeter", "centimeters"], factor: 0.01, dimension: .length, label: "cm"),
    Unit(names: ["mm", "millimeter", "millimeters"], factor: 0.001, dimension: .length, label: "mm"),
    Unit(names: ["mi", "mile", "miles"], factor: 1609.344, dimension: .length, label: "mi"),
    Unit(names: ["ft", "foot", "feet"], factor: 0.3048, dimension: .length, label: "ft"),
    Unit(names: ["in", "inch", "inches"], factor: 0.0254, dimension: .length, label: "in"),
    Unit(names: ["yd", "yard", "yards"], factor: 0.9144, dimension: .length, label: "yd"),
    Unit(names: ["kg", "kilogram", "kilograms", "kilo", "kilos"], factor: 1, dimension: .mass, label: "kg"),
    Unit(names: ["g", "gram", "grams"], factor: 0.001, dimension: .mass, label: "g"),
    Unit(names: ["mg", "milligram", "milligrams"], factor: 0.000_001, dimension: .mass, label: "mg"),
    Unit(names: ["lb", "lbs", "pound", "pounds"], factor: 0.453_592_37, dimension: .mass, label: "lb"),
    Unit(names: ["oz", "ounce", "ounces"], factor: 0.028_349_523, dimension: .mass, label: "oz"),
    Unit(names: ["l", "liter", "liters", "litre", "litres"], factor: 1, dimension: .volume, label: "L"),
    Unit(names: ["ml", "milliliter", "milliliters"], factor: 0.001, dimension: .volume, label: "mL"),
    Unit(names: ["gal", "gallon", "gallons"], factor: 3.785_411_784, dimension: .volume, label: "gal"),
    Unit(names: ["qt", "quart", "quarts"], factor: 0.946_352_946, dimension: .volume, label: "qt"),
    Unit(names: ["cup", "cups"], factor: 0.236_588_236, dimension: .volume, label: "cup"),
    Unit(names: ["floz"], factor: 0.029_573_53, dimension: .volume, label: "fl oz"),
    Unit(names: ["s", "sec", "second", "seconds"], factor: 1, dimension: .time, label: "s"),
    Unit(names: ["min", "minute", "minutes"], factor: 60, dimension: .time, label: "min"),
    Unit(names: ["h", "hr", "hour", "hours"], factor: 3600, dimension: .time, label: "h"),
    Unit(names: ["d", "day", "days"], factor: 86_400, dimension: .time, label: "d"),
    Unit(names: ["wk", "week", "weeks"], factor: 604_800, dimension: .time, label: "wk"),
    Unit(names: ["b", "byte", "bytes"], factor: 1, dimension: .data, label: "B"),
    Unit(names: ["kb"], factor: 1000, dimension: .data, label: "KB"),
    Unit(names: ["mb"], factor: 1_000_000, dimension: .data, label: "MB"),
    Unit(names: ["gb"], factor: 1_000_000_000, dimension: .data, label: "GB"),
    Unit(names: ["tb"], factor: 1_000_000_000_000, dimension: .data, label: "TB"),
    Unit(names: ["kib"], factor: 1024, dimension: .data, label: "KiB"),
    Unit(names: ["mib"], factor: 1_048_576, dimension: .data, label: "MiB"),
    Unit(names: ["gib"], factor: 1_073_741_824, dimension: .data, label: "GiB"),
    Unit(names: ["mps", "m/s"], factor: 1, dimension: .speed, label: "m/s"),
    Unit(names: ["kph", "km/h", "kmh"], factor: 1 / 3.6, dimension: .speed, label: "km/h"),
    Unit(names: ["mph"], factor: 0.447_04, dimension: .speed, label: "mph"),
    Unit(names: ["kn", "knot", "knots"], factor: 0.514_444, dimension: .speed, label: "kn"),
    Unit(names: ["c", "celsius", "°c"], factor: 1, dimension: .temperature, label: "°C"),
    Unit(names: ["f", "fahrenheit", "°f"], factor: 1, dimension: .temperature, label: "°F"),
    Unit(names: ["k", "kelvin"], factor: 1, dimension: .temperature, label: "K"),
  ]

  /// "10 km to mi", "72 f in c", "5 gb -> mb".
  static func convert(_ text: String) -> ThunderConversion? {
    let pattern = #"^\s*(-?\d+(?:[.,]\d+)?)\s*([a-z°/]+)\s+(?:to|in|as|->)\s+([a-z°/]+)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 4,
      let r1 = Range(match.range(at: 1), in: text), let r2 = Range(match.range(at: 2), in: text),
      let r3 = Range(match.range(at: 3), in: text),
      let value = Double(text[r1].replacingOccurrences(of: ",", with: ".")),
      let from = unit(String(text[r2])), let to = unit(String(text[r3])),
      from.dimension == to.dimension
    else { return nil }
    let result: Double
    if from.dimension == .temperature {
      result = fromCelsius(toCelsius(value, from.label), to.label)
    } else {
      result = value * from.factor / to.factor
    }
    guard result.isFinite else { return nil }
    return ThunderConversion(value: value, from: from.label, to: to.label, result: result)
  }

  private static func unit(_ name: String) -> Unit? {
    let key = name.lowercased()
    return units.first { $0.names.contains(key) }
  }

  private static func toCelsius(_ v: Double, _ label: String) -> Double {
    switch label {
    case "°F": (v - 32) * 5 / 9
    case "K": v - 273.15
    default: v
    }
  }

  private static func fromCelsius(_ v: Double, _ label: String) -> Double {
    switch label {
    case "°F": v * 9 / 5 + 32
    case "K": v + 273.15
    default: v
    }
  }
}
