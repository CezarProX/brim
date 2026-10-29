import AppKit
import SwiftUI

/// Lets the whole top bar drag the window (the title bar is transparent and merged with the content).
private struct WindowDragArea: NSViewRepresentable {
  final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
  }
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The floating Notes window: the same notes as the island, with a sidebar, search and the full toolbar.
struct NotesWindowView: View {
  @ObservedObject var notes: NotesModel
  var sendToNotch: (UUID) -> Void = { _ in }
  @StateObject private var controller = NoteEditorController()
  @AppStorage("notesWindowSidebar") private var sidebarShown = true
  @AppStorage("notesWindowFontSize") private var fontSize = 14.0
  @State private var query = ""
  @FocusState private var searchFocused: Bool
  private let tint = Color(red: 1, green: 0.8, blue: 0.2)

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Divider().overlay(IslandFill.hairline)
      HStack(spacing: 0) {
        if sidebarShown {
          sidebar.frame(width: 210)
          Divider().overlay(IslandFill.hairline)
        }
        editorColumn
      }
    }
    .background { GlassWindowBackdrop(forcesDark: true).ignoresSafeArea() }
    .ignoresSafeArea(.container, edges: .top)
    .foregroundStyle(IslandInk.primary)
    .preferredColorScheme(.dark)
  }

  // MARK: Top bar

  private var topBar: some View {
    HStack(spacing: 4) {
      Spacer().frame(width: 74)
      Text(notes.selected?.title ?? L10n.tr("Notes"))
        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
      Spacer(minLength: 8)
      Menu {
        ForEach([(L10n.tr("Small"), 12.0), (L10n.tr("Medium"), 14.0), (L10n.tr("Large"), 17.0)], id: \.1) { title, size in
          Button(title) { fontSize = size }
        }
      } label: {
        Text("Aa").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 26)
      }
      .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L10n.tr("Text size"))
      barButton("magnifyingglass", L10n.tr("Search notes")) {
        sidebarShown = true
        searchFocused = true
      }
      barButton("square.and.pencil", L10n.tr("New note")) { notes.create() }
      barButton("sidebar.left", L10n.tr("Toggle sidebar")) { sidebarShown.toggle() }
      moreMenu
    }
    .padding(.horizontal, 12).frame(height: 40)
    .background(WindowDragArea())
  }

  private func barButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.secondary)
        .frame(width: 28, height: 26).contentShape(Rectangle())
    }
    .buttonStyle(.plain).help(help).accessibilityLabel(help)
  }

  private var moreMenu: some View {
    Menu {
      if let note = notes.selected {
        Button(note.pinned ? L10n.tr("Unpin") : L10n.tr("Pin")) { notes.togglePin(note.id) }
        Button(L10n.tr("Copy note")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(note.text, forType: .string)
        }
        Button(L10n.tr("Send to notch")) { sendToNotch(note.id) }
        Divider()
        Button(L10n.tr("Delete note"), role: .destructive) { notes.delete(note.id) }
      }
    } label: {
      Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 26)
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L10n.tr("More"))
    .disabled(notes.selected == nil)
  }

  // MARK: Sidebar

  private var shown: [IslandNote] { NotesModel.filter(notes.notes, query: query) }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
        TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
      }
      .padding(.horizontal, 8).frame(height: 26).glassCard(radius: 7)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(shown) { note in row(note) }
          if shown.isEmpty {
            Text(query.isEmpty ? "No notes yet" : "No matches").font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
              .padding(.top, 8).padding(.horizontal, 6)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .padding(10).background(Color.white.opacity(0.035))
  }

  private func row(_ note: IslandNote) -> some View {
    Button {
      notes.selectedID = note.id
    } label: {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(note.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(note.edited.formatted(.relative(presentation: .named))).font(.system(size: 10)).foregroundStyle(IslandInk.tertiary)
        }
        Spacer(minLength: 0)
        if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(tint) }
      }
      .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
      .background(note.id == notes.selectedID ? IslandFill.raised : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(note.pinned ? L10n.tr("Unpin") : L10n.tr("Pin")) { notes.togglePin(note.id) }
      Button(L10n.tr("Delete note"), role: .destructive) { notes.delete(note.id) }
    }
  }

  // MARK: Editor

  @ViewBuilder private var editorColumn: some View {
    if let note = notes.selected {
      VStack(spacing: 0) {
        NoteFormatBar(controller: controller, full: true)
          .padding(.horizontal, 12).frame(height: 38).frame(maxWidth: .infinity, alignment: .leading)
        Divider().overlay(IslandFill.hairline)
        NoteRichEditor(
          markdown: NotesBinding.markdown(for: note.id, in: notes), controller: controller,
          style: .window(size: fontSize), autofocus: true
        )
        .id(note.id).padding(.horizontal, 14).padding(.top, 4)
      }
    } else {
      VStack(spacing: 10) {
        Image(systemName: "note.text").font(.system(size: 30)).foregroundStyle(tint)
        Text("No notes yet").font(.system(size: 14, weight: .semibold))
        Button("New note") { notes.create() }.buttonStyle(IslandPillStyle(prominent: true, tint: tint, compact: true))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
