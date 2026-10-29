import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Loads Finder-quality previews once per path.
@MainActor
final class FileThumbnailCache: ObservableObject {
  static let shared = FileThumbnailCache()
  @Published private var images: [String: NSImage] = [:]
  private var pending: Set<String> = []

  func image(for url: URL, size: CGFloat = 128) -> NSImage {
    if let image = images[url.path] { return image }
    load(url, size: size)
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  private func load(_ url: URL, size: CGFloat) {
    guard !pending.contains(url.path) else { return }
    pending.insert(url.path)
    if images.count > 300 { images.removeAll() }
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: size, height: size), scale: 2, representationTypes: .all)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
      guard let image = thumbnail?.nsImage else { return }
      Task { @MainActor in
        self?.images[url.path] = image
        self?.pending.remove(url.path)
      }
    }
  }
}


/// The File Tray page: large QuickLook thumbnails with their names in rows of four,
/// click to select, double-click to open, drag out, right-click for the file menu. Select-all and
/// the Basket sit as two small round buttons at the bottom right.
@MainActor
struct FileTrayView: View {
  @ObservedObject var store: FileTrayStore
  @ObservedObject private var thumbnails = FileThumbnailCache.shared
  @State private var selection: Set<UUID>
  @State private var renaming: FileTrayItem?
  @State private var newName = ""
  @State private var working = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(store: FileTrayStore, selection: Set<UUID> = []) {
    self.store = store
    _selection = State(initialValue: selection)
  }

  private var selected: [FileTrayItem] {
    let chosen = store.items.filter { selection.contains($0.id) }
    return chosen.isEmpty ? store.items : chosen
  }

  private var rows: [[FileTrayItem]] {
    stride(from: 0, to: store.items.count, by: FileTrayGrid.columns).map {
      Array(store.items[$0..<min($0 + FileTrayGrid.columns, store.items.count)])
    }
  }

  var body: some View {
    Group {
      if store.items.isEmpty {
        dropHint.transition(.opacity)
      } else {
        grid.overlay(alignment: .bottomTrailing) { cornerButtons }
      }
    }
    .overlay(alignment: .bottomLeading) { messageToast }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: store.message)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: store.items)
    .popover(item: $renaming) { item in renamePopover(item) }
    .onChange(of: store.items) { _, items in
      selection.formIntersection(Set(items.map(\.id)))
    }
    .shelfKeyboardShortcuts(shortcutHandlers)
  }

  /// Cmd+A, Esc, Delete, Cmd+C and Return on the files the user picked (see ShelfKeyboardShortcuts).
  private var shortcutHandlers: ShelfShortcutHandlers {
    func items(_ ids: Set<UUID>) -> [FileTrayItem] { store.items.filter { ids.contains($0.id) } }
    return ShelfShortcutHandlers(
      items: store.items.map(\.id), selection: selection,
      selectAll: { ids in withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection = ids } },
      deselect: { withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection = [] } },
      remove: { ids in remove(items(ids)) },
      copy: { ids in ShelfPasteboard.copy(items(ids).map { store.url(for: $0) }) },
      open: { ids in store.open(items(ids)) })
  }

  private var grid: some View {
    ScrollView(.vertical) {
      VStack(spacing: FileTrayGrid.rowSpacing) {
        ForEach(rows.indices, id: \.self) { index in
          HStack(spacing: 0) {
            ForEach(rows[index]) { item in tile(item) }
          }
          .frame(height: FileTrayGrid.rowHeight)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.top, FileTrayGrid.topPadding)
      .padding(.bottom, FileTrayGrid.bottomPadding)
    }
    .scrollIndicators(.hidden)
  }

  private func tile(_ item: FileTrayItem) -> some View {
    let url = store.url(for: item)
    return FileTile(
      url: url, missing: !store.exists(item), thumbnail: thumbnails.image(for: url, size: 320),
      selected: selection.contains(item.id), pinned: item.pinned,
      drag: { store.dragProvider(for: item) },
      remove: { remove([item]) }
    ) {
      toggle(item)
    } open: {
      store.open([item])
    }
    .contextMenu {
      FileTrayMenu(
        items: selection.contains(item.id) ? selected : [item], store: store,
        rename: { item in
          newName = store.url(for: item).lastPathComponent
          renaming = item
        },
        run: run, remove: remove)
    }
    .transition(.scale(scale: 0.8).combined(with: .opacity))
  }

  private var cornerButtons: some View {
    let allSelected = !store.items.isEmpty && selection.count == store.items.count
    return HStack(spacing: 6) {
      if working { ProgressView().controlSize(.small).padding(.trailing, 4) }
      if !selection.isEmpty {
        roundButton("trash", label: "Remove Selected", highlighted: false) {
          remove(store.items.filter { selection.contains($0.id) })
        }
        .transition(.scale.combined(with: .opacity))
      }
      roundButton(
        allSelected ? "checkmark.circle.fill" : "checkmark", label: allSelected ? "Deselect All" : "Select All",
        highlighted: allSelected
      ) {
        withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
          selection = allSelected ? [] : Set(store.items.map(\.id))
        }
      }
      roundButton("basket", label: "Move to Basket", highlighted: false) {
        FloatingBasketController.shared.receive(selected.map { store.url(for: $0) })
      }
    }
    .padding(.trailing, 22).padding(.bottom, 14)
  }

  private func roundButton(
    _ symbol: String, label: String, highlighted: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .bold))
        .foregroundStyle(highlighted ? Color.blue : IslandInk.primary.opacity(0.85))
        .frame(width: 32, height: 32)
        .background(Color(white: 0.22).opacity(0.92), in: Circle())
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.86))
    .help(label)
    .accessibilityLabel(label)
  }

  private var dropHint: some View {
    VStack(spacing: 7) {
      Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .regular))
        .foregroundStyle(IslandInk.secondary)
      Text("Drop files here").font(.system(size: 14, weight: .semibold))
      Text("They wait in the notch until you drag them where they belong.")
        .font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 28).padding(.vertical, 18)
  }

  @ViewBuilder private var messageToast: some View {
    if let message = store.message {
      Text(message).font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.black.opacity(0.7), in: Capsule())
        .padding(.leading, 24).padding(.bottom, 14)
        .transition(.opacity)
    }
  }

  private func renamePopover(_ item: FileTrayItem) -> some View {
    HStack {
      TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 200)
        .onSubmit { commitRename(item) }
      Button("Rename") { commitRename(item) }.keyboardShortcut(.defaultAction)
    }
    .padding(12)
  }

  private func commitRename(_ item: FileTrayItem) {
    store.rename(item, to: newName)
    renaming = nil
  }

  private func remove(_ items: [FileTrayItem]) {
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      store.remove(Set(items.map(\.id)))
    }
  }

  private func toggle(_ item: FileTrayItem) {
    withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
      if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }
  }

  private func run(_ work: @escaping @MainActor () async -> Void) {
    working = true
    Task {
      await work()
      working = false
    }
  }
}

/// One file: thumbnail (rounded, on a dark plate with a blue check when selected) over its name.
private struct FileTile: View {
  let url: URL
  let missing: Bool
  let thumbnail: NSImage
  let selected: Bool
  var pinned = false
  let drag: () -> NSItemProvider
  let remove: () -> Void
  let toggle: () -> Void
  let open: () -> Void
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Pictures and videos show as a filled landscape card; other files keep their icon.
  private var isMedia: Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .image) || type.conforms(to: .movie)
  }

  @ViewBuilder private var preview: some View {
    if isMedia {
      Image(nsImage: thumbnail).resizable().scaledToFill()
        .frame(width: FileTrayGrid.mediaWidth, height: FileTrayGrid.thumbnail)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
        }
    } else {
      Image(nsImage: thumbnail).resizable().scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .frame(width: FileTrayGrid.thumbnail, height: FileTrayGrid.thumbnail)
    }
  }

  var body: some View {
    VStack(spacing: 9) {
      preview
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .opacity(missing ? 0.35 : 1)
        .padding(5)
        .background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Color.white.opacity(0.16) : .clear)
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.14 : 0), lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 17, weight: .semibold))
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, Color.blue)
              .background(Circle().fill(.black).padding(-1.5))
              .offset(y: 9)
              .transition(.scale.combined(with: .opacity))
          }
        }
        .overlay(alignment: .topLeading) {
          if hovered {
            Button(action: remove) {
              Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(white: 0.28), in: Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.8))
            .offset(x: -4, y: -4)
            .help("Remove from Tray")
            .accessibilityLabel("Remove \(url.lastPathComponent) from Tray")
            .transition(.scale(scale: 0.5).combined(with: .opacity))
          }
        }
        .overlay(alignment: .topTrailing) {
          if pinned {
            Image(systemName: "pin.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
              .padding(4).background(Color.orange, in: Circle()).offset(x: 2, y: -2)
              .accessibilityHidden(true)
          }
        }
        .scaleEffect(hovered && !reduceMotion ? 1.05 : 1)
      Text(url.lastPathComponent)
        .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
        .foregroundStyle(missing ? IslandInk.tertiary : IslandInk.primary)
        .frame(width: FileTrayGrid.columnWidth - 8)
    }
    .frame(width: FileTrayGrid.columnWidth)
    .contentShape(Rectangle())
    .onTapGesture(count: 2, perform: open)
    .onTapGesture(perform: toggle)
    .onDrag(drag)
    .onHover { hovered = $0 }
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: hovered)
    .help(missing ? "\(url.lastPathComponent) was moved or deleted" : url.path)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(url.lastPathComponent)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityValue(pinned ? "Pinned" : "")
  }
}
