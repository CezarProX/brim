import Foundation

/// Best-effort two-way sync with a "Brim" folder in Apple Notes. Newest edit wins; nothing is deleted.
@MainActor
final class AppleNotesSync: ObservableObject {
  static let shared = AppleNotesSync()
  @Published private(set) var status: String?
  @Published private(set) var syncing = false

  var enabled: Bool { AppSettings.shared.appleNotesSyncEnabled }

  func sync(notes: NotesModel) async {
    guard enabled, !syncing else { return }
    syncing = true
    defer { syncing = false }
    do {
      let output = try await AppleScriptRunner.run(AppleNotesBridge.readScript, timeout: 20)
      let plan = NotesSyncPlan.make(local: notes.notes, remote: AppleNotesBridge.parse(output))
      try await apply(plan, to: notes)
      status = "Synced with Apple Notes"
    } catch {
      status = "Apple Notes didn’t answer. Allow Brim to control Notes in System Settings → Privacy & Security → Automation."
    }
  }

  private func apply(_ plan: NotesSyncPlan, to notes: NotesModel) async throws {
    for (id, remote) in plan.pullUpdate {
      notes.update(id, text: remote.text, now: remote.modified)
    }
    for note in plan.pullCreate {
      notes.merge([IslandNote(id: UUID(), text: note.text, edited: note.modified, appleID: note.id)])
    }
    for id in plan.pushCreate {
      guard let note = notes.notes.first(where: { $0.id == id }) else { continue }
      let appleID = try await AppleScriptRunner.run(AppleNotesBridge.createScript(text: note.text), timeout: 15)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !appleID.isEmpty { notes.setAppleID(appleID, for: id) }
    }
    for id in plan.pushUpdate {
      guard let note = notes.notes.first(where: { $0.id == id }), let appleID = note.appleID,
        let script = AppleNotesBridge.updateScript(id: appleID, text: note.text)
      else { continue }
      _ = try await AppleScriptRunner.run(script, timeout: 15)
    }
  }
}
