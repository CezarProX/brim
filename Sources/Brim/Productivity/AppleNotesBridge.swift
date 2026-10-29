import Foundation

/// A note read from the "Brim" folder in Apple Notes.
struct AppleNote: Equatable {
  let id: String
  let modified: Date
  let text: String
}

enum AppleNotesBridge {
  static let folder = "Brim"
  static let recordSeparator = "\u{1E}"
  static let fieldSeparator = "\u{1F}"

  /// Creates the folder if needed, then lists notes as `id US seconds-from-now US plaintext RS ...`.
  static let readScript = """
    tell application "Notes"
      if not (exists folder "\(folder)") then make new folder with properties {name:"\(folder)"}
      set output to ""
      set nowDate to current date
      repeat with n in notes of folder "\(folder)"
        set offset to ((modification date of n) - nowDate) as integer
        set output to output & (id of n) & (ASCII character 31) & offset & (ASCII character 31) & (plaintext of n) & (ASCII character 30)
      end repeat
      return output
    end tell
    """

  static func parse(_ output: String, now: Date = .now) -> [AppleNote] {
    output.components(separatedBy: recordSeparator).prefix(200).compactMap { record in
      let trimmed = record.trimmingCharacters(in: .newlines)
      let fields = trimmed.components(separatedBy: fieldSeparator)
      guard fields.count >= 3, !fields[0].isEmpty, let offset = Double(fields[1]) else { return nil }
      return AppleNote(
        id: fields[0], modified: now.addingTimeInterval(offset),
        text: fields[2...].joined(separator: fieldSeparator).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  static func html(for text: String) -> String {
    let lines = text.components(separatedBy: "\n").map { line -> String in
      let escaped = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
      return escaped
    }
    let title = (lines.first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    let rest = lines.dropFirst().map { $0.isEmpty ? "<div><br></div>" : "<div>\($0)</div>" }
    return "<h1>\(title)</h1>" + rest.joined()
  }

  static func createScript(text: String) -> String {
    "tell application \"Notes\" to return id of (make new note at folder \"\(folder)\" with properties {body:\(AppleScriptRunner.quote(html(for: text)))})"
  }

  /// nil when the id isn't one Notes would produce.
  static func updateScript(id: String, text: String) -> String? {
    guard id.hasPrefix("x-coredata://"), id.count < 300, !id.contains("\"") else { return nil }
    return "tell application \"Notes\" to set body of note id \(AppleScriptRunner.quote(id)) to \(AppleScriptRunner.quote(html(for: text)))"
  }

  /// Text comparison that ignores markdown headings and surrounding whitespace.
  static func normalized(_ text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    if let first = lines.first { lines[0] = first.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// What a two-way sync pass should do. Newest edit wins; nothing is ever deleted.
struct NotesSyncPlan: Equatable {
  var pushCreate: [UUID] = []
  var pushUpdate: [UUID] = []
  var pullCreate: [AppleNote] = []
  var pullUpdate: [(UUID, AppleNote)] = []

  static func == (lhs: NotesSyncPlan, rhs: NotesSyncPlan) -> Bool {
    lhs.pushCreate == rhs.pushCreate && lhs.pushUpdate == rhs.pushUpdate && lhs.pullCreate == rhs.pullCreate
      && lhs.pullUpdate.map(\.0) == rhs.pullUpdate.map(\.0)
  }

  static func make(local: [IslandNote], remote: [AppleNote], tolerance: TimeInterval = 2) -> NotesSyncPlan {
    var plan = NotesSyncPlan()
    var seen = Set<String>()
    for note in local {
      guard let appleID = note.appleID, let match = remote.first(where: { $0.id == appleID }) else {
        // Empty notes are not worth creating in Apple Notes.
        if note.appleID == nil, !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          plan.pushCreate.append(note.id)
        }
        continue
      }
      seen.insert(match.id)
      guard AppleNotesBridge.normalized(note.text) != AppleNotesBridge.normalized(match.text) else { continue }
      if match.modified.timeIntervalSince(note.edited) > tolerance {
        plan.pullUpdate.append((note.id, match))
      } else if note.edited.timeIntervalSince(match.modified) > tolerance {
        plan.pushUpdate.append(note.id)
      }
    }
    let known = Set(local.compactMap(\.appleID))
    plan.pullCreate = remote.filter { !known.contains($0.id) && !seen.contains($0.id) }
    return plan
  }
}
