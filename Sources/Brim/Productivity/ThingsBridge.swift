import AppKit
import Foundation

/// A to-do read from Things 3's Today list.
struct ThingsTodo: Identifiable, Equatable {
  let id: String
  let title: String
  let project: String?
  /// Due date as yyyymmdd, when the to-do has a deadline.
  let due: Date?
  let tags: [String]
}

/// Pure pieces of the Things 3 bridge: the AppleScript, its output parser and the URL scheme.
enum ThingsScripts {
  static let bundleID = "com.culturedcode.ThingsMac"
  static let fieldSeparator = "\t"

  /// Read-only: one line per to-do, `id TAB name TAB project TAB yyyymmdd TAB tag,tag`.
  static let readToday = """
    tell application "Things3"
      set output to ""
      repeat with t in to dos of list "Today"
        set projectName to ""
        try
          set projectName to name of project of t
        end try
        set dueText to ""
        try
          set d to deadline of t
          if d is not missing value then
            set dueText to ((year of d) * 10000 + ((month of d) as integer) * 100 + (day of d)) as text
          end if
        end try
        set output to output & (id of t) & tab & (name of t) & tab & projectName & tab & dueText & tab & (tag names of t) & linefeed
      end repeat
      return output
    end tell
    """

  static func parse(_ output: String, calendar: Calendar = .current) -> [ThingsTodo] {
    output.split(whereSeparator: \.isNewline).prefix(200).compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 2, isValidID(fields[0]), !fields[1].isEmpty else { return nil }
      let project = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
      let tags = fields.count > 4
        ? fields[4].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        : []
      return ThingsTodo(
        id: fields[0], title: String(fields[1].prefix(300)), project: project,
        due: fields.count > 3 ? date(fromCompact: fields[3], calendar: calendar) : nil, tags: tags)
    }
  }

  static func date(fromCompact text: String, calendar: Calendar) -> Date? {
    guard text.count == 8, let value = Int(text) else { return nil }
    return calendar.date(from: DateComponents(year: value / 10_000, month: value / 100 % 100, day: value % 100))
  }

  /// Things ids are short base-62 strings; anything else never reaches a script.
  static func isValidID(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
  }

  static func complete(id: String) -> String? {
    guard isValidID(id) else { return nil }
    return "tell application \"Things3\" to set status of to do id \"\(id)\" to completed"
  }

  /// things:///add?title=...&when=today
  static func addURL(title: String, notes: String? = nil, when: String = "today") -> URL? {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, clean.count <= 500 else { return nil }
    var components = URLComponents()
    components.scheme = "things"
    components.host = ""
    components.path = "/add"
    components.queryItems = [URLQueryItem(name: "title", value: clean), URLQueryItem(name: "when", value: when)]
      + (notes.map { [URLQueryItem(name: "notes", value: String($0.prefix(2000)))] } ?? [])
    return components.url
  }
}

@MainActor
final class ThingsModel: ObservableObject {
  static let shared = ThingsModel()
  @Published private(set) var todos: [ThingsTodo] = []
  @Published private(set) var status: String?

  var isInstalled: Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: ThingsScripts.bundleID) != nil
  }

  var enabled: Bool { isInstalled && AppSettings.shared.thingsBridgeEnabled }

  func refresh() async {
    guard enabled else { todos = []; return }
    do {
      let output = try await AppleScriptRunner.run(ThingsScripts.readToday)
      todos = ThingsScripts.parse(output)
      status = nil
    } catch {
      status = "Things didn’t answer. Allow Brim to control Things in System Settings → Privacy & Security → Automation."
    }
  }

  func complete(_ todo: ThingsTodo) async {
    guard let script = ThingsScripts.complete(id: todo.id) else { return }
    todos.removeAll { $0.id == todo.id }
    do { _ = try await AppleScriptRunner.run(script) } catch {
      status = "Couldn’t complete the to-do in Things."
      await refresh()
    }
  }

  @discardableResult
  func add(_ title: String) -> Bool {
    guard let url = ThingsScripts.addURL(title: title) else { return false }
    NSWorkspace.shared.open(url)
    return true
  }
}
