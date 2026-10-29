import SwiftUI

/// The selected note as the island shows it: compact formatting bar over the rich editor.
struct IslandNoteEditor: View {
  @ObservedObject var notes: NotesModel
  @StateObject private var controller = NoteEditorController()

  var body: some View {
    if let note = notes.selected {
      VStack(alignment: .leading, spacing: 6) {
        NoteFormatBar(controller: controller)
        NoteRichEditor(markdown: NotesBinding.markdown(for: note.id, in: notes), controller: controller, style: .island)
          .id(note.id)
          .padding(.horizontal, 4)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .glassCard(radius: IslandRadius.small + 2)
      }
    }
  }
}

enum NotesBinding {
  /// Two-way link between one note's Markdown and the model, shared by the island and the window.
  @MainActor
  static func markdown(for id: UUID, in notes: NotesModel) -> Binding<String> {
    Binding(
      get: { notes.notes.first { $0.id == id }?.text ?? "" },
      set: { text in
        // Only a real change moves the note to the top of the list.
        if notes.notes.first(where: { $0.id == id })?.text != text { notes.update(id, text: text) }
      })
  }
}
