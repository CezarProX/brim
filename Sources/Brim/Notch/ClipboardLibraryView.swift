import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardLibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", pinned = "Pinned", screenshots = "Screenshots", images = "Images", text = "Text",
         links = "Links", colors = "Colors", files = "Files"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .pinned: return "star.fill"
        case .screenshots: return "camera.viewfinder"
        case .images: return "photo"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .colors: return "paintpalette.fill"
        case .files: return "doc.fill"
        }
    }
}

/// Screenshots retain their ShelfStore identity; clipboard content has separate bounded storage.
@MainActor
struct ClipboardLibraryView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var clipboard: ClipboardStore
    var onConfirmationChange: (Bool) -> Void
    var onShare: ((URL) -> Void)?
    @State private var query = ""
    @State private var filter: ClipboardLibraryFilter = .all
    @State private var feedback: String?
    @State private var confirmClear = false
    @State private var tagFilter: ClipboardTag?
    @State private var searching = false
    @State private var editing: ClipboardEntry?
    @State private var pinboard: ClipboardPinboard?
    @State private var selection = ClipboardSelection()
    @State private var taggingTargets = false
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    private let settings: AppSettings
    @Namespace private var filterSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ShelfStore, clipboard: ClipboardStore? = nil,
         onConfirmationChange: @escaping (Bool) -> Void = { _ in },
         onShare: ((URL) -> Void)? = nil, settings: AppSettings = .shared,
         preselected: [String] = []) {
        var initial = ClipboardSelection()
        initial.selectAll(preselected)
        initial.cursor = preselected.last
        _selection = State(initialValue: initial)
        self.settings = settings
        // The filmed demo (`--demo`) swaps in sample history and an empty screenshot shelf.
        self.store = DemoController.shelfOverride ?? store
        self.clipboard = clipboard ?? DemoController.clipboardOverride ?? .shared
        self.onConfirmationChange = onConfirmationChange
        self.onShare = onShare
    }

    private var enabledPinboards: [ClipboardPinboard] { ClipboardPinboard.enabled(in: settings) }
    private var activePinboard: ClipboardPinboard? { pinboard.flatMap { enabledPinboards.contains($0) ? $0 : nil } }

    private var items: [LibraryItem] {
        let all = store.entries.map(LibraryItem.screenshot) + clipboard.entries.map(LibraryItem.clipboard)
        let board = activePinboard
        let visible = all.filter { item in
            let matchesKind = filter == .all || (filter == .pinned && item.isPinned)
                || (filter == .screenshots && item.isScreenshot)
                || (filter == .images && item.kind == .image && !item.isScreenshot)
                || (filter == .text && item.kind == .text) || (filter == .links && item.kind == .link)
                || (filter == .colors && item.kind == .color) || (filter == .files && item.kind == .file)
            let matchesTag = tagFilter.map { item.tag == $0 } ?? true
            let matchesBoard = board.map { board in item.clipboardEntry.map(board.matches) ?? false } ?? true
            return matchesKind && matchesTag && matchesBoard
                && (query.isEmpty || item.searchText.localizedCaseInsensitiveContains(query))
        }
        return ClipboardPolicy.displayOrder(visible, date: \.date, pinned: \.isPinned,
                                            placement: settings.clipboardPinnedPlacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpace.s + 2) {
            toolbar
            if !enabledPinboards.isEmpty { pinboardTabs }
            if searching {
                HStack(spacing: IslandSpace.s) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandInk.tertiary)
                    TextField(feedback ?? "Search \(items.count) items", text: $query)
                        .textFieldStyle(.plain).font(IslandFont.body)
                        .focused($searchFocused)
                        .accessibilityLabel("Search library")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(IslandInk.tertiary)
                        }
                        .buttonStyle(IslandPressStyle()).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, IslandSpace.m).frame(height: 28)
                .background(IslandFill.subtle, in: Capsule())
                .transition(.islandDrop)
            }
            if items.isEmpty { emptyState.transition(.opacity) }
            else {
                // The history is laid out as one horizontal strip of cards.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(items) { item in
                                card(item).frame(width: 150).id(item.id)
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .islandScrollRegion()
                    .onChange(of: selection.cursor) { _, id in
                        guard let id else { return }
                        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            if let error = clipboard.errorMessage ?? store.errorMessage {
                Text(error).font(IslandFont.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: items.map(\.id))
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .background { shortcutButtons }
        .onAppear { focusOnOpen() }
        .onChange(of: items.map(\.id)) { _, ids in selection.prune(keeping: ids) }
        .popover(isPresented: $taggingTargets, arrowEdge: .bottom) { tagPicker }
        .onChange(of: confirmClear) { _, value in onConfirmationChange(value) }
        .onDisappear { onConfirmationChange(false) }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear unpinned history", role: .destructive) { clipboard.clearUnpinned() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes unpinned cached text, links and copied images. Pins, screenshots and your current clipboard stay unchanged.") }
        .popover(item: $editing) { entry in
            ClipboardEditPopover(text: entry.text ?? "") { text in
                feedback = clipboard.edit(entry, text: text) ? "Saved" : "Couldn’t save"
                editing = nil
            }
        }
    }

    /// The toolbar: search, icon filters, the "Clipboard" pill and tag pills.
    private var toolbar: some View {
        HStack(spacing: 2) {
            filterIcon("magnifyingglass", label: "Search", selected: searching) {
                withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
                    searching.toggle()
                    if !searching { query = "" }
                }
            }
            ForEach(ClipboardLibraryFilter.allCases) { choice in
                filterIcon(choice.symbol, label: choice.rawValue, selected: filter == choice && tagFilter == nil) {
                    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
                        filter = choice
                        tagFilter = nil
                        feedback = nil
                    }
                }
            }
            if selection.isEmpty {
                Label(feedback ?? "Clipboard", systemImage: "clock.arrow.circlepath")
                    .font(IslandFont.caption.weight(.semibold)).foregroundStyle(IslandInk.secondary)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(IslandFill.subtle, in: Capsule())
                    .contentTransition(.opacity)
                    .fixedSize()
            } else {
                selectionCapsule
            }
            ForEach(ClipboardTag.allCases) { tag in
                Button {
                    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
                        tagFilter = tagFilter == tag ? nil : tag
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(Color(nsColor: tag.color)).frame(width: 7, height: 7)
                        Text(tag.title.lowercased()).font(IslandFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(tagFilter == tag ? IslandInk.primary : IslandInk.secondary)
                    .padding(.horizontal, 6).frame(height: 24)
                    .background(tagFilter == tag ? IslandFill.raised : .clear, in: Capsule())
                    .contentShape(Capsule())
                    .fixedSize()
                }
                .buttonStyle(IslandPressStyle())
                .accessibilityAddTraits(tagFilter == tag ? .isSelected : [])
            }
            Spacer(minLength: 0)
            options
        }
    }

    /// Smart pinboards: automatic tabs that gather every matching clip.
    private var pinboardTabs: some View {
        HStack(spacing: 4) {
            ForEach(enabledPinboards) { board in
                let selected = activePinboard == board
                Button {
                    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
                        pinboard = selected ? nil : board
                    }
                } label: {
                    Label(board.title, systemImage: board.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(IslandFont.caption.weight(.semibold))
                        .foregroundStyle(selected ? IslandInk.primary : IslandInk.secondary)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(selected ? IslandFill.selected : IslandFill.subtle, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(IslandPressStyle(pressedScale: 0.94))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func filterIcon(_ symbol: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? IslandInk.primary : IslandInk.tertiary)
                .frame(width: 23, height: 24)
                .background {
                    if selected {
                        Circle().fill(IslandFill.raised)
                            .matchedGeometryEffect(id: "library-filter", in: filterSelection)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.85))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var options: some View {
        Menu {
            Button("New screenshot") { CaptureCoordinator.shared.startCapture() }
            Divider()
            Button(clipboard.isMonitoring ? "Pause clipboard history" : "Resume clipboard history") {
                if clipboard.isMonitoring { clipboard.stop() } else { clipboard.start() }
            }
            Button("Clear unpinned clipboard history…", role: .destructive) { confirmClear = true }
                .disabled(!clipboard.entries.contains { !$0.isPinned })
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandInk.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 22).accessibilityLabel("Library options")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 22, weight: .medium)).foregroundStyle(IslandInk.tertiary)
            Text(query.isEmpty ? "Nothing here yet" : "No results")
                .font(IslandFont.headline)
            Text(query.isEmpty ? "Copied images, text and links appear here." : "Try another search or filter.")
                .font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: LibraryItem) -> some View {
        ClipboardCard(
            item: item, detail: detail(for: item), onCopy: { copy(item) },
            onTogglePin: item.clipboardEntry.map { entry in { togglePin(entry) } },
            mark: mark(for: item)
        ) {
            Button { primaryAction(item) } label: {
                preview(item).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.98))
            .help(item.kind == .image ? "Click to edit screenshot or copy image" : "Copy to clipboard")
            .onDrag { dragProvider(item) }
        }
        .contextMenu { itemMenu(item) }
    }

    @ViewBuilder
    private func preview(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .image: imagePreview(item)
        case .color: colorPreview(item)
        case .file: filePreview(item)
        default: textPreview(item)
        }
    }

    private func colorPreview(_ item: LibraryItem) -> some View {
        let color = item.clipboardEntry?.text.flatMap(ClipboardEntry.color(from:)) ?? .gray
        return RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous)
            .fill(Color(nsColor: color))
            .overlay(alignment: .bottomLeading) {
                Text(item.clipboardEntry?.text ?? "").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 2).padding(6)
            }
            .padding(8)
    }

    private func filePreview(_ item: LibraryItem) -> some View {
        let urls = item.clipboardEntry?.fileURLs ?? []
        return VStack(spacing: 4) {
            if let first = urls.first {
                Image(nsImage: FileThumbnailCache.shared.image(for: first)).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
            }
            Text(urls.count > 1 ? "\(urls.first?.lastPathComponent ?? "") +\(urls.count - 1)" : urls.first?.lastPathComponent ?? "")
                .font(IslandFont.caption).lineLimit(1).padding(.horizontal, 8)
        }
    }

    private func detail(for item: LibraryItem) -> String {
        switch item {
        case .screenshot(let entry): return entry.pixelSize
        case .clipboard(let entry):
            switch entry.kind {
            case .image: return entry.pixelSize ?? "Image"
            case .color: return entry.text ?? "Color"
            case .file:
                let urls = entry.fileURLs
                return urls.count == 1 ? (urls[0].pathExtension.uppercased().isEmpty ? "Folder" : urls[0].pathExtension.uppercased())
                    : "\(urls.count) files"
            case .link: return ClipboardEntry.webURL(entry.text ?? "")?.host ?? "Link"
            case .text:
                let count = entry.text?.count ?? 0
                return count == 1 ? "1 character" : "\(count) characters"
            }
        }
    }

    private func imagePreview(_ item: LibraryItem) -> some View {
        let image: NSImage?
        switch item {
        case .screenshot(let entry): image = store.thumbnail(for: entry)
        case .clipboard(let entry): image = clipboard.thumbnail(for: entry)
        }
        return ZStack {
            Color.white.opacity(0.03)
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(5) }
            else { Image(systemName: "photo").foregroundStyle(IslandInk.tertiary) }
            if item.ocrText != nil {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(6)
                    .background(.black.opacity(0.72), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(7)
                    .help("Text detected locally")
                    .accessibilityLabel("Text detected in image")
            }
        }
    }

    private func textPreview(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.kind == .link {
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IslandTint.color(for: .transfer))
            }
            Text(item.title).font(IslandFont.label).lineLimit(item.kind == .link ? 3 : 5)
                .foregroundStyle(IslandInk.primary.opacity(0.88)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func itemMenu(_ item: LibraryItem) -> some View {
        Button("Copy") { copy(item) }
        switch item {
        case .screenshot(let entry):
            if let onShare {
                Button("Share…") { onShare(store.fileURL(for: entry)) }
            }
            Button("Edit screenshot") { NotchShelfController.shared.edit(entry) }
            Button("Save As…") { NotchShelfController.shared.save(entry) }
            Divider()
            Button("Remove from library", role: .destructive) { store.remove(entry) }
        case .clipboard(let entry):
            Button(entry.isPinned ? "Unpin" : "Pin") { togglePin(entry) }
            if [.text, .link, .color].contains(entry.kind) {
                Button("Edit…") { editing = entry }
            }
            Menu("Tag") {
                ForEach(ClipboardTag.allCases) { tag in
                    Button {
                        _ = clipboard.setTag(entry, entry.tag == tag ? nil : tag)
                    } label: { Label(tag.title, systemImage: entry.tag == tag ? "checkmark" : "circle.fill") }
                }
                if entry.tag != nil { Divider(); Button("Remove Tag") { _ = clipboard.setTag(entry, nil) } }
            }
            Button(entry.isBlurred ? "Show Content" : "Blur Content") {
                _ = clipboard.setBlurred(entry, !entry.isBlurred)
            }
            if entry.kind == .file {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(entry.fileURLs) }
                Button("Add to Shelf") { FileTrayStore.shared.add(entry.fileURLs) }
            }
            if entry.kind == .image {
                if entry.ocrText != nil {
                    Button("Copy detected text") { copyRecognizedText(entry) }
                }
                Button("Edit image") { edit(entry) }
                Button("Save As…") { save(entry) }
            }
            if entry.kind == .link, let text = entry.text, let url = ClipboardEntry.webURL(text) {
                Button("Open link in browser") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Remove from library", role: .destructive) { clipboard.remove(entry) }
        }
    }

    private func primaryAction(_ item: LibraryItem) {
        // ⌘-click, or any click while a selection is open, picks the card instead of copying it.
        if NSEvent.modifierFlags.contains(.command) || !selection.isEmpty {
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection.toggle(item.id) }
            return
        }
        if case .screenshot(let entry) = item { NotchShelfController.shared.edit(entry) }
        else { copy(item) }
    }

    private func copy(_ item: LibraryItem) {
        var copied = false
        switch item {
        case .screenshot(let entry):
            if let image = store.image(for: entry) { CaptureActions.copyToClipboard(image); feedback = "Copied"; copied = true }
        case .clipboard(let entry):
            copied = clipboard.copy(entry)
            feedback = copied ? "Copied" : "Couldn’t copy"
            if copied, settings.clipboardCopyAndFavorite, !entry.isPinned { _ = clipboard.setPinned(entry, true) }
        }
        if copied, settings.clipboardPasteOnSelect, ClipboardPaster.isAccessibilityTrusted {
            // Close the island first so the previous app is frontmost again, then send ⌘V.
            NotchShelfController.shared.dismissShelf()
            ClipboardPaster.shared.pasteIntoPreviousApp()
            feedback = nil
        }
    }

    private func copyRecognizedText(_ entry: ClipboardEntry) {
        feedback = clipboard.copyRecognizedText(entry) ? "Detected text copied" : "Text unavailable"
    }

    private func togglePin(_ entry: ClipboardEntry) {
        feedback = clipboard.setPinned(entry, !entry.isPinned)
            ? (entry.isPinned ? "Unpinned" : "Pinned") : "Couldn’t update pin"
    }

    private func edit(_ entry: ClipboardEntry) {
        guard let data = clipboard.imageData(for: entry), let image = NSImage(data: data) else { return }
        NotchShelfController.shared.dismissShelf()
        let editedID = UUID()
        ShelfEditorWindowController.open(image: image) { image in store.add(image, id: editedID) }
    }

    private func save(_ entry: ClipboardEntry) {
        guard let data = clipboard.imageData(for: entry), let image = NSImage(data: data) else { return }
        NotchShelfController.shared.dismissShelf()
        CaptureActions.save(image, from: nil, forceSavePanel: true)
    }

    private func dragProvider(_ item: LibraryItem) -> NSItemProvider {
        switch item {
        case .screenshot(let entry):
            guard let data = try? Data(contentsOf: store.fileURL(for: entry)) else { return NSItemProvider() }
            return imageDragProvider(data, date: entry.date)
        case .clipboard(let entry):
            if entry.kind == .file, let url = entry.fileURLs.first {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            if let text = entry.text {
                if entry.kind == .link, let url = ClipboardEntry.webURL(text) { return NSItemProvider(object: url as NSURL) }
                return NSItemProvider(object: text as NSString)
            }
            guard let data = clipboard.imageData(for: entry) else { return NSItemProvider() }
            return imageDragProvider(data, date: entry.date)
        }
    }

    /// A real PNG file for chat apps, plus the image data for editors (see ImageDragExport).
    private func imageDragProvider(_ data: Data, date: Date) -> NSItemProvider {
        if let provider = ImageDragExport.provider(for: data, date: date) { return provider }
        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
    }
}

// MARK: - Keyboard, multi-select and Paste All

extension ClipboardLibraryView {
    func mark(for item: LibraryItem) -> ClipboardCardMark {
        if let index = selection.ordered.firstIndex(of: item.id) { return .selected(index + 1) }
        return selection.cursor == item.id ? .cursor : .none
    }

    /// The items a command acts on, in selection order (or just the cursor item).
    private func targetItems() -> [LibraryItem] {
        let visible = items
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selection.targets(in: visible.map(\.id)).compactMap { byID[$0] }
    }

    func focusOnOpen() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if settings.clipboardAutoFocusSearch {
                searching = true
                searchFocused = true
            } else {
                listFocused = true
            }
        }
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        let key: ClipboardKey
        switch press.key {
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .return: key = .returnKey
        case .escape: key = .escape
        case .delete, .deleteForward: key = .delete
        default:
            guard let character = press.characters.first else { return .ignored }
            key = .character(character)
        }
        // ⌘-letters are owned by the hidden shortcut buttons, which macOS routes before key presses.
        if command, case .character = key { return .ignored }
        guard let shortcut = ClipboardShortcuts.command(
            for: key, command: command, shift: press.modifiers.contains(.shift),
            option: press.modifiers.contains(.option), searching: searchFocused)
        else { return .ignored }
        return perform(shortcut) ? .handled : .ignored
    }

    /// Runs a keyboard command. Returns false when it did nothing, so the key can fall through.
    @discardableResult
    func perform(_ shortcut: ClipboardShortcut) -> Bool {
        let ids = items.map(\.id)
        let chosen = targetItems()
        switch shortcut {
        case .move(let delta):
            if searchFocused { searchFocused = false; listFocused = true }
            selection.move(delta, in: ids)
            return !ids.isEmpty
        case .cancel:
            if searchFocused { searchFocused = false; listFocused = true; return true }
            guard !selection.isEmpty else { return false }
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection.clear() }
            return true
        case .focusSearch:
            withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { searching = true }
            searchFocused = true
            return true
        case .toggleSelect:
            guard let cursor = selection.cursor else { return false }
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection.toggle(cursor) }
            return true
        case .selectAll:
            withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
                if selection.count == ids.count { selection.clear() } else { selection.selectAll(ids) }
            }
            return true
        case .activate:
            if !selection.isEmpty { pasteAll(); return true }
            guard let cursor = selection.cursor, let item = items.first(where: { $0.id == cursor }) else { return false }
            primaryAction(item)
            return true
        case .pasteAll: return pasteAll()
        case .copy: return copyTargets(chosen)
        case .deleteItem: return deleteTargets(chosen)
        case .togglePin: return toggleOnTargets(chosen, current: \.isPinned) { clipboard.setPinned($0, $1) }
        case .toggleBlur: return toggleOnTargets(chosen, current: \.isBlurred) { clipboard.setBlurred($0, $1) }
        case .saveAs:
            guard let item = chosen.first(where: { $0.kind == .image }) else { return false }
            switch item {
            case .screenshot(let entry): NotchShelfController.shared.save(entry)
            case .clipboard(let entry): save(entry)
            }
            return true
        case .tag:
            guard chosen.contains(where: { $0.clipboardEntry != nil }) else { return false }
            taggingTargets = true
            return true
        }
    }

    private func copyTargets(_ chosen: [LibraryItem]) -> Bool {
        guard let first = chosen.first else { return false }
        guard chosen.count > 1 else { copy(first); return true }
        let written = clipboard.copyTogether(chosen.compactMap(\.clipboardEntry))
        feedback = written > 0 ? "Copied \(chosen.count) items" : "Couldn’t copy"
        return true
    }

    private func deleteTargets(_ chosen: [LibraryItem]) -> Bool {
        guard !chosen.isEmpty else { return false }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
            for item in chosen {
                switch item {
                case .screenshot(let entry): store.remove(entry)
                case .clipboard(let entry): clipboard.remove(entry)
                }
            }
            selection.clear()
            selection.cursor = nil
        }
        feedback = chosen.count == 1 ? "Removed" : "Removed \(chosen.count) items"
        return true
    }

    /// Flips a flag on every chosen clipboard entry: off if all have it, on otherwise.
    private func toggleOnTargets(_ chosen: [LibraryItem], current: KeyPath<ClipboardEntry, Bool>,
                                 apply: (ClipboardEntry, Bool) -> Bool) -> Bool {
        let entries = chosen.compactMap(\.clipboardEntry)
        guard !entries.isEmpty else { return false }
        let turnOn = !entries.allSatisfy { $0[keyPath: current] }
        for entry in entries { _ = apply(entry, turnOn) }
        return true
    }

    /// Copies the chosen entries and pastes them into the app that was in front. Without Accessibility
    /// they are only copied. Mixed kinds (images among text) paste one after another.
    @discardableResult
    func pasteAll() -> Bool {
        let entries = targetItems().compactMap(\.clipboardEntry)
        guard !entries.isEmpty else { return false }
        let plan = ClipboardPastePlan.plan(for: entries.map(\.kind))
        let canPaste = ClipboardPaster.isAccessibilityTrusted
        selection.clear()
        guard canPaste else {
            let written = plan == .sequential ? (clipboard.copy(entries[entries.count - 1]) ? 1 : 0)
                : clipboard.copyTogether(entries)
            feedback = written > 0 ? "Copied \(entries.count) items" : "Couldn’t copy"
            return true
        }
        NotchShelfController.shared.dismissShelf()
        if plan == .sequential {
            Task { @MainActor in
                for (index, entry) in entries.enumerated() {
                    guard clipboard.copy(entry) else { continue }
                    ClipboardPaster.shared.pasteIntoPreviousApp(after: index == 0 ? 0.28 : 0.02)
                    try? await Task.sleep(for: .milliseconds(index == 0 ? 700 : 450))
                }
            }
        } else if clipboard.copyTogether(entries) > 0 {
            ClipboardPaster.shared.pasteIntoPreviousApp()
        }
        return true
    }

    var selectionCapsule: some View {
        HStack(spacing: 6) {
            Button { pasteAll() } label: {
                Label("Paste \(selection.count)", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.94))
            .help("Paste the selected items in the order you picked them (⌘↩)")
            Button { withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { selection.clear() } } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.85)).accessibilityLabel("Clear selection")
        }
        .font(IslandFont.caption.weight(.semibold)).foregroundStyle(.white)
        .padding(.horizontal, 8).frame(height: 24)
        .background(Color.blue.opacity(0.85), in: Capsule())
        .fixedSize()
        .transition(.scale.combined(with: .opacity))
    }

    var tagPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClipboardTag.allCases) { tag in
                Button { applyTag(tag) } label: {
                    Label(tag.title, systemImage: "circle.fill").foregroundStyle(Color(nsColor: tag.color), .primary)
                }
            }
            Divider()
            Button("Remove Tag") { applyTag(nil) }
        }
        .buttonStyle(.plain).padding(10)
    }

    private func applyTag(_ tag: ClipboardTag?) {
        for entry in targetItems().compactMap(\.clipboardEntry) { _ = clipboard.setTag(entry, tag) }
        taggingTargets = false
    }

    /// Invisible buttons that carry the ⌘ shortcuts. Disabled while the search field has focus so
    /// ⌘C/⌘A/⌘P act on the typed text there; ⌘F always works.
    var shortcutButtons: some View {
        Group {
            shortcut("c", .command, .copy)
            shortcut("d", .command, .deleteItem)
            shortcut("f", .command, .focusSearch)
            shortcut("p", .command, .togglePin)
            shortcut("b", .command, .toggleBlur)
            shortcut("s", [.command, .shift], .saveAs)
            shortcut("t", .command, .tag)
            shortcut("a", .command, .selectAll)
            shortcut(.return, .command, .pasteAll)
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, _ command: ClipboardShortcut) -> some View {
        Button("") { perform(command) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(searchFocused && command != .focusSearch)
    }
}
