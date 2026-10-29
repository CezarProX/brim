import SwiftUI

/// The Notes and Obsidian apps as the island opens them. Notes are quick notes kept on this Mac;
/// Obsidian edits the Markdown files of a vault. Each tile shows only its own app.
@MainActor
struct NotesPanelView: View {
  enum Mode: String { case notes = "Notes", obsidian = "Obsidian" }

  @ObservedObject var notes: NotesModel
  @ObservedObject var obsidian: ObsidianModel
  private let mode: Mode
  private let preview: Bool

  static let noteTint = Color(red: 1, green: 0.8, blue: 0.2)
  static let obsidianTint = Color(red: 0.62, green: 0.45, blue: 0.95)

  /// Tile for the Widgets page (Obsidian can use the same view with its own tile).
  static let tile = (title: "Notes", symbol: "note.text", tint: noteTint)
  static let obsidianTile = (title: "Obsidian", symbol: "diamond.fill", tint: obsidianTint)

  init(notes: NotesModel? = nil, obsidian: ObsidianModel? = nil, mode: Mode? = nil, preview: Bool = false) {
    _notes = ObservedObject(wrappedValue: notes ?? .shared)
    _obsidian = ObservedObject(wrappedValue: obsidian ?? .shared)
    self.mode = mode ?? (AppSettings.shared.notesBackendName == "obsidian" ? .obsidian : .notes)
    self.preview = preview
  }

  var body: some View {
    switch mode {
    case .notes: NotesIslandPane(notes: notes)
    case .obsidian: ObsidianIslandPane(model: obsidian, preview: preview)
    }
  }
}

// MARK: - Notes

private struct NotesIslandPane: View {
  @ObservedObject var notes: NotesModel
  @ObservedObject private var sync = AppleNotesSync.shared
  @State private var query = ""
  private let tint = NotesPanelView.noteTint

  var body: some View {
    Group {
      if notes.notes.isEmpty {
        AppEmptyState(
          symbol: "note.text", tint: tint, title: "No notes yet",
          message: "Jot down a thought, a list or a link. Notes save as you type and stay on this Mac.",
          primaryTitle: "New Note", primaryAction: { notes.create() })
      } else {
        HStack(alignment: .top, spacing: IslandSpace.m) {
          sidebar.frame(width: 190)
          editorPane
        }
      }
    }
    .onAppear { if sync.enabled { Task { await sync.sync(notes: notes) } } }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        AppSearchField(text: $query)
        AppIconButton(symbol: "square.and.pencil", label: "New note", tint: tint) { query = ""; notes.create() }
      }
      let shown = NotesModel.filter(notes.notes, query: query)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if shown.isEmpty {
            Text("No matches").font(IslandFont.body).foregroundStyle(IslandInk.tertiary).padding(.top, 6).padding(.leading, 8)
          }
          ForEach(shown) { note in
            AppListRow(
              title: note.title.isEmpty ? L10n.tr("New note") : note.title,
              subtitle: note.edited.formatted(.relative(presentation: .named)),
              selected: note.id == notes.selectedID, pinned: note.pinned, tint: tint
            ) { notes.selectedID = note.id }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var editorPane: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let note = notes.selected {
        HStack(spacing: 6) {
          Text(note.title.isEmpty ? L10n.tr("New note") : note.title).font(IslandFont.headline).lineLimit(1)
          Spacer(minLength: 0)
          if sync.enabled, let status = sync.status {
            Text(status).font(IslandFont.label).foregroundStyle(IslandInk.tertiary).lineLimit(1)
          }
          AppIconButton(symbol: "doc.on.doc", label: "Copy note") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.text, forType: .string)
          }
          AppIconButton(symbol: "macwindow", label: "Open in window") {
            NotesWindowController.shared.show(noteID: note.id)
            NotchShelfController.shared.dismissShelf()
          }
          AppIconButton(symbol: note.pinned ? "pin.slash" : "pin", label: note.pinned ? "Unpin" : "Pin") {
            notes.togglePin(note.id)
          }
          AppIconButton(symbol: "trash", label: "Delete") { notes.delete(note.id) }
        }
        IslandNoteEditor(notes: notes)
      } else {
        AppEmptyState(symbol: "note.text", tint: tint, title: "Select a note", message: "Pick a note on the left, or start a new one.")
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

// MARK: - Shared list pieces

/// A 28 pt search capsule for the sidebars.
struct AppSearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
      TextField("Search", text: $text).textFieldStyle(.plain).font(IslandFont.body)
    }
    .padding(.horizontal, 10).frame(height: 28).background(IslandFill.subtle, in: Capsule())
  }
}

/// One row of a sidebar list: a title, a quiet second line and an optional pin.
struct AppListRow: View {
  let title: String
  let subtitle: String
  let selected: Bool
  var pinned = false
  let tint: Color
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
          if !subtitle.isEmpty {
            Text(verbatim: subtitle).font(IslandFont.body).foregroundStyle(IslandInk.tertiary).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(tint) }
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
      .background(selected ? IslandFill.raised : (hovered ? IslandFill.subtle : .clear), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .accessibilityLabel(title)
  }
}
