import Foundation

/// Where a quick-add entry goes: an event calendar or a Reminders list.
struct QuickAddDestination: Identifiable, Equatable, Hashable {
  enum Kind: String, Equatable { case calendar, reminderList }
  let id: String
  let name: String
  let kind: Kind
}

/// What the user typed, split into the text to parse and the "@" destination state.
struct QuickAddInput: Equatable {
  /// The text with any "@destination" removed.
  let body: String
  /// The destination name written after a completed "@", if any.
  let destinationName: String?
  /// Characters after a trailing, still-open "@"; non-nil means the destination menu is showing.
  let openQuery: String?

  static func split(_ text: String, known: [String] = []) -> QuickAddInput {
    // An "@" being typed at the very end opens the menu, unless it already names a destination.
    if let open = text.range(of: #"(?:^|\s)@([^\s"]*)$"#, options: .regularExpression),
      !known.contains(where: { text[open].trimmingCharacters(in: .whitespaces).dropFirst().lowercased() == $0.lowercased() })
    {
      let token = String(text[open]).trimmingCharacters(in: .whitespaces)
      let body = String(text[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
      return QuickAddInput(body: body, destinationName: nil, openQuery: String(token.dropFirst()))
    }
    let pattern = #"(?:^|\s)@(?:"([^"]+)"|(\S+))"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let whole = Range(match.range, in: text)
    else { return QuickAddInput(body: text, destinationName: nil, openQuery: nil) }
    let quoted = Range(match.range(at: 1), in: text).map { String(text[$0]) }
    let bare = Range(match.range(at: 2), in: text).map { String(text[$0]) }
    var body = text
    body.removeSubrange(whole)
    return QuickAddInput(
      body: body.trimmingCharacters(in: .whitespaces),
      destinationName: (quoted ?? bare)?.replacingOccurrences(of: "_", with: " "), openQuery: nil)
  }

  /// The token inserted when a destination is picked from the menu.
  static func token(for destination: QuickAddDestination) -> String {
    destination.name.contains(where: \.isWhitespace) ? "@\"\(destination.name)\"" : "@\(destination.name)"
  }

  /// Replaces the open "@query" with a completed destination token.
  static func completing(_ text: String, with destination: QuickAddDestination) -> String {
    guard let open = text.range(of: #"(?:^|\s)@([^\s"]*)$"#, options: .regularExpression) else {
      return text
    }
    let lead = text[open].first?.isWhitespace == true ? " " : ""
    return String(text[..<open.lowerBound]) + lead + token(for: destination) + " "
  }
}

enum QuickAddDestinations {
  /// Case-insensitive match: exact, then prefix, then substring.
  static func resolve(_ name: String, in all: [QuickAddDestination]) -> QuickAddDestination? {
    let needle = name.lowercased()
    guard !needle.isEmpty else { return nil }
    return all.first { $0.name.lowercased() == needle }
      ?? all.first { $0.name.lowercased().hasPrefix(needle) }
      ?? all.first { $0.name.lowercased().contains(needle) }
  }

  /// Menu rows for an open "@query": reminder lists first, then calendars.
  static func menu(matching query: String, in all: [QuickAddDestination]) -> [QuickAddDestination] {
    let needle = query.lowercased()
    let hits = needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    return hits.filter { $0.kind == .reminderList } + hits.filter { $0.kind == .calendar }
  }
}

/// A fully interpreted quick-add entry, ready to save as an event or a reminder.
struct QuickAddPlan: Equatable {
  enum Output: Equatable {
    case event(CalendarQuickAdd.Draft)
    case reminder(title: String, due: Date?, hasTime: Bool)
  }

  let output: Output
  let destination: QuickAddDestination?

  static func make(
    _ text: String, destinations: [QuickAddDestination], now: Date = .now,
    calendar: Calendar = .current
  ) -> QuickAddPlan? {
    var input = QuickAddInput.split(text, known: destinations.map(\.name))
    // Submitting while the menu is open accepts a unique-enough prefix, like "@Wo" for Work.
    if let query = input.openQuery, !query.isEmpty,
      let match = QuickAddDestinations.resolve(query, in: destinations)
    {
      input = QuickAddInput(body: input.body, destinationName: match.name, openQuery: nil)
    }
    guard input.openQuery == nil else { return nil }
    let destination = input.destinationName.flatMap { QuickAddDestinations.resolve($0, in: destinations) }
    let draft = CalendarQuickAdd.parse(input.body, now: now, calendar: calendar)
    if destination?.kind == .reminderList {
      let title = draft?.title ?? input.body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return nil }
      return QuickAddPlan(
        output: .reminder(title: title, due: draft?.start, hasTime: draft.map { !$0.isAllDay } ?? false),
        destination: destination)
    }
    guard let draft else { return nil }
    return QuickAddPlan(output: .event(draft), destination: destination)
  }
}
