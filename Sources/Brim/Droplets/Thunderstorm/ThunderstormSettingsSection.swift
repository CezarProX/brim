import SwiftUI

/// Launcher settings: on/off, shortcut, what it searches, web fallback, quicklinks and snippets.
struct ThunderstormSettingsSection: View {
  @State private var enabled = AppSettings.shared.thunderstormEnabled
  @State private var shortcut = AppSettings.shared.thunderstormShortcut
  @State private var files = AppSettings.shared.thunderstormSearchFiles
  @State private var clipboard = AppSettings.shared.thunderstormSearchClipboard
  @State private var system = AppSettings.shared.thunderstormSystemCommands
  @State private var web = AppSettings.shared.thunderstormWebTemplate
  @State private var links = AppSettings.shared.thunderstormQuicklinks
  @State private var snippets = AppSettings.shared.thunderstormSnippets

  var body: some View {
    SettingsSection("Thunderstorm launcher") {
      Toggle("Open a search panel with a shortcut", isOn: $enabled)
        .settingsAnchor("launcher.enable")
        .onChange(of: enabled) { _, value in
          AppSettings.shared.thunderstormEnabled = value
          ThunderstormController.shared.start()
        }
      Text("Find apps, files, clipboard history, quicklinks and snippets; do math and unit conversions; run system commands. Everything stays on this Mac. Files come from Spotlight, so Spotlight must be on.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        DropletShortcutField(title: "Shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.thunderstormShortcut = value
            ThunderstormController.shared.start()
          }
        Toggle("Search files (Spotlight)", isOn: $files).onChange(of: files) { _, v in AppSettings.shared.thunderstormSearchFiles = v }
        Toggle("Search clipboard history", isOn: $clipboard).onChange(of: clipboard) { _, v in AppSettings.shared.thunderstormSearchClipboard = v }
        Toggle("System commands (sleep display, lock, empty Trash, dark mode)", isOn: $system)
          .onChange(of: system) { _, v in AppSettings.shared.thunderstormSystemCommands = v }
        TextField("Web search address (use {query})", text: $web).textFieldStyle(.roundedBorder)
          .onChange(of: web) { _, value in
            if ThunderQuicklink.expand(value, query: "test") != nil { AppSettings.shared.thunderstormWebTemplate = value }
          }
        if ThunderQuicklink.expand(web, query: "test") == nil {
          Text("That isn’t a valid web address template, so the previous one stays in use.").font(.caption).foregroundStyle(.orange)
        }
        quicklinks
        snippetList
      }
    }
  }

  private var quicklinks: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Quicklinks").font(.subheadline.weight(.medium))
        Spacer()
        Button("Add") { links.append(ThunderQuicklink(keyword: "", name: "New quicklink", template: "https://example.com/?q={query}")) }
      }
      Text("Type the keyword, a space, then your text: “gh swift” opens the address with {query} replaced.")
        .font(.footnote).foregroundStyle(.secondary)
      ForEach($links) { $link in
        HStack {
          TextField("Keyword", text: $link.keyword).frame(width: 70)
          TextField("Name", text: $link.name).frame(width: 130)
          TextField("https://…{query}", text: $link.template)
          Button { links.removeAll { $0.id == link.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)
      }
    }
    .onChange(of: links) { _, value in AppSettings.shared.thunderstormQuicklinks = value }
  }

  private var snippetList: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Snippets").font(.subheadline.weight(.medium))
        Spacer()
        Button("Add") { snippets.append(ThunderSnippet(keyword: "", title: "New snippet", text: "")) }
      }
      Text("Choose a snippet in the launcher and its text is pasted into the app you were in. {date}, {time} and {clipboard} are filled in.")
        .font(.footnote).foregroundStyle(.secondary)
      ForEach($snippets) { $snippet in
        HStack(alignment: .top) {
          TextField("Keyword", text: $snippet.keyword).frame(width: 70)
          TextField("Title", text: $snippet.title).frame(width: 130)
          TextField("Text", text: $snippet.text, axis: .vertical).lineLimit(1...4)
          Button { snippets.removeAll { $0.id == snippet.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)
      }
    }
    .onChange(of: snippets) { _, value in AppSettings.shared.thunderstormSnippets = value }
  }
}
