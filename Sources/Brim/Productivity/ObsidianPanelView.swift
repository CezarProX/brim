import SwiftUI

/// The Obsidian app: the notes of a vault, edited in place. The vault Obsidian has open is found
/// on its own; without one, the first screen asks for a folder.
struct ObsidianIslandPane: View {
  @ObservedObject var model: ObsidianModel
  @State var preview: Bool
  @State private var query = ""
  private let tint = NotesPanelView.obsidianTint

  init(model: ObsidianModel, preview: Bool = false) {
    self.model = model
    _preview = State(initialValue: preview)
  }

  var body: some View {
    Group {
      if model.vault == nil {
        connect
      } else {
        HStack(alignment: .top, spacing: IslandSpace.m) {
          sidebar.frame(width: 190)
          editorPane
        }
      }
    }
    .onAppear { model.reload() }
    .onDisappear { model.flush() }
  }

  // MARK: First run

  private var connect: some View {
    let installed = ObsidianAppLink.isInstalled
    return AppEmptyState(
      symbol: "diamond.fill", tint: tint, title: "Connect your vault",
      message: installed
        ? "Open a vault in Obsidian and it shows up here by itself, or pick the vault folder yourself."
        : "Pick the folder that holds your Markdown notes. Brim reads and edits the files directly.",
      primaryTitle: "Choose Vault Folder…", primaryAction: { model.chooseVault() },
      secondaryTitle: installed ? "Open Obsidian" : "Get Obsidian",
      secondaryAction: {
        if installed, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ObsidianAppLink.bundleID) {
          NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "https://obsidian.md") {
          NSWorkspace.shared.open(url)
        }
      },
      footnote: "Changes save to the files as you type.")
  }

  // MARK: Sidebar

  private var isLinked: Bool { model.followsObsidian && model.vault != nil }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      vaultMenu
      HStack(spacing: 6) {
        AppSearchField(text: $query)
        AppIconButton(symbol: "calendar.badge.plus", label: "Today’s daily note", tint: tint) { model.openDailyNote() }
        AppIconButton(symbol: "square.and.pencil", label: "New note", tint: tint) { model.createNote() }
      }
      let shown = model.files.filter { query.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(query) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          if shown.isEmpty {
            Text(model.files.isEmpty ? "This vault has no notes yet" : "No matches")
              .font(IslandFont.body).foregroundStyle(IslandInk.tertiary).padding(.top, 6).padding(.leading, 8)
          }
          ForEach(shown.prefix(60)) { file in
            AppListRow(
              title: file.title,
              subtitle: file.relativePath.contains("/") ? (file.relativePath as NSString).deletingLastPathComponent : "",
              selected: file.relativePath == model.selectedPath, tint: tint
            ) { model.select(file.relativePath) }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  /// The current vault and whether it follows the Obsidian app, with a menu to switch.
  private var vaultMenu: some View {
    Menu {
      ForEach(model.knownVaults) { known in
        Button {
          model.useKnownVault(known)
        } label: {
          if known.path == model.vault?.root.path && !model.followsObsidian {
            Label(known.name, systemImage: "checkmark")
          } else {
            Text(known.name)
          }
        }
      }
      if !model.knownVaults.isEmpty { Divider() }
      Button {
        model.followObsidian()
      } label: {
        if model.followsObsidian {
          Label("Follow the Obsidian app", systemImage: "checkmark")
        } else {
          Text("Follow the Obsidian app")
        }
      }
      .disabled(model.knownVaults.isEmpty)
      Button("Choose folder…") { model.chooseVault() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundStyle(tint)
        Text(verbatim: model.vault?.name ?? L10n.tr("No vault")).font(IslandFont.headline).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandInk.tertiary)
      }
      .foregroundStyle(IslandInk.primary).padding(.horizontal, 10).frame(height: 28)
      .background(IslandFill.subtle, in: Capsule())
      .contentShape(Capsule())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    .help(isLinked ? L10n.tr("Following the vault open in Obsidian") : L10n.tr("Vault chosen by hand"))
    .accessibilityLabel("Vault: \(model.vault?.name ?? "none")")
  }

  // MARK: Editor

  private var editorPane: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(verbatim: paneTitle).font(IslandFont.headline).lineLimit(1)
        Spacer(minLength: 0)
        if model.selectedPath != nil {
          AppIconButton(symbol: preview ? "pencil" : "eye", label: preview ? "Edit" : "Preview") { preview.toggle() }
        }
        AppIconButton(symbol: "arrow.up.forward.app", label: "Open in Obsidian") { model.openInObsidian() }
      }
      if let error = model.error {
        Text(verbatim: error).font(IslandFont.body).foregroundStyle(IslandTint.recording)
      }
      if model.selectedPath != nil {
        noteContent
      } else {
        AppEmptyState(
          symbol: "diamond", tint: tint, title: "Pick a note",
          message: "Choose a note on the left, or open today’s daily note.",
          primaryTitle: "Today’s Note", primaryAction: { model.openDailyNote() })
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var paneTitle: String {
    model.selectedPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? model.vault?.name ?? "Obsidian"
  }

  private var noteContent: some View {
    let binding = Binding(get: { model.text }, set: { model.text = $0; model.edited() })
    return ZStack {
      if preview {
        MarkdownPreview(text: binding.wrappedValue) { binding.wrappedValue = MarkdownLite.toggleCheckbox(in: binding.wrappedValue, line: $0) }
      } else {
        TextEditor(text: binding).font(IslandFont.body).scrollContentBackground(.hidden).scrollIndicators(.hidden)
      }
    }
    .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
    .glassCard(radius: IslandRadius.small + 2)
  }
}
