import AppKit
import SwiftUI

/// The "Edit screenshot" window. A separate editing session; the original
/// shelf image is never overwritten -- Done hands the rendered result to
/// `onSaveToShelf`, which stores it as a new shelf entry.
///
/// `open(image:onSaveToShelf:)` is a stable entry point used by the shelf,
/// the clipboard library and the post-capture thumbnail.
@MainActor
final class ShelfEditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: [UUID: ShelfEditorWindowController] = [:]
    private let identifier = UUID()
    let model: ScreenshotEditorModel
    private let onSaveToShelf: (NSImage) -> Void
    private let toolbarController = EditorWindowToolbar()
    private var isSaving = false
    private var allowsClose = false

    /// Where an edited capture goes when Done is pressed: the Shelf, or, with the Shelf off, the
    /// clipboard (with a flash), so an edit is never silently dropped.
    static func keepEdited(_ image: NSImage, id: UUID) {
        if AppSettings.shared.notchShelfEnabled {
            ShelfStore.shared.add(image, id: id)
        } else {
            CaptureActions.copyToClipboard(image)
            IslandFlashCenter.shared.show(L10n.tr("Copied"), symbol: "doc.on.doc.fill", tint: .blue)
        }
    }

    static func open(image: NSImage, onSaveToShelf: @escaping (NSImage) -> Void) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let controller = ShelfEditorWindowController(image: image, onSaveToShelf: onSaveToShelf)
        openEditors[controller.identifier] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(image: NSImage, onSaveToShelf: @escaping (NSImage) -> Void, presets: StylePresetStore? = nil) {
        self.model = ScreenshotEditorModel(image: image, presets: presets)
        self.onSaveToShelf = onSaveToShelf
        let window = ShelfEditorWindow(
            contentRect: CGRect(origin: .zero, size: Self.initialContentSize()),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configure(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func initialContentSize() -> CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: min(1280, max(860, screen.width - 120)), height: min(840, max(600, screen.height - 120)))
    }

    private func configure(_ window: ShelfEditorWindow) {
        window.title = L10n.tr("Edit screenshot")
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.105, green: 0.105, blue: 0.115, alpha: 1)
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 760, height: 520)
        window.delegate = self
        window.toolbarStyle = .unified
        toolbarController.onToggleSidebar = { [weak self] in self?.model.isSidebarVisible.toggle() }
        toolbarController.onDone = { [weak self] in self?.done() }
        toolbarController.shareItems = { [weak self] in self.map { [$0.model.renderedImage()] } ?? [] }
        window.toolbar = toolbarController.makeToolbar()
        window.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
        window.contentView = NSHostingView(rootView: ScreenshotEditorView(model: model))
        window.center()
        window.makeFirstResponder(model.canvasHost.canvas)
    }

    // MARK: - Actions

    func done() {
        let rendered = model.renderedImage()
        onSaveToShelf(rendered)
        model.markSaved()
        closeWithoutPrompt()
    }

    func copyImage() {
        CaptureActions.copyToClipboard(model.renderedImage())
    }

    func saveImage() {
        guard !isSaving else { return }
        let rendered = model.renderedImage()
        let saveToShelf = onSaveToShelf
        isSaving = true
        CaptureActions.save(rendered, from: window, onCompletion: { [weak self] in
            self?.isSaving = false
        }, onSuccess: { [weak self] in
            saveToShelf(rendered)
            self?.model.markSaved()
        }, forceSavePanel: true)
    }

    /// Closes, first asking whether to discard unsaved edits.
    func requestClose() {
        guard model.isEdited, let window else {
            closeWithoutPrompt()
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Discard your edits?")
        alert.informativeText = L10n.tr("Your annotations and background changes to this screenshot will be lost.")
        alert.addButton(withTitle: L10n.tr("Discard"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.closeWithoutPrompt() }
        }
    }

    private func closeWithoutPrompt() {
        allowsClose = true
        close()
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let session = model.session
        guard let command = EditorKeyCommand.command(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags, isEditingText: session.isEditingText
        ) else { return false }
        perform(command)
        return true
    }

    func perform(_ command: EditorKeyCommand) {
        switch command {
        case .escape:
            if model.session.isEditingText { model.session.endTextEditing() }
            else if model.currentTool == .crop { model.select(tool: nil) }
            else { requestClose() }
        case .close: requestClose()
        case .copy: copyImage()
        case .save: saveImage()
        case .done: done()
        case .undo: model.undo()
        case .redo: model.redo()
        case .delete: model.deleteSelection()
        case .zoomIn: model.zoomIn()
        case .zoomOut: model.zoomOut()
        case .actualSize: model.zoomToActualSize()
        case .zoomToFit: model.zoomToFit()
        case .toggleSidebar: model.isSidebarVisible.toggle()
        case .tool(let tool):
            if model.currentTool != tool { model.select(tool: tool) }
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsClose || !model.isEdited { return true }
        requestClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.session.endTextEditing()
        Self.openEditors.removeValue(forKey: identifier)
    }
}

/// Routes key presses to the editor before normal dispatch, unless a
/// regular text control (preset name field, colour panel) has focus.
@MainActor
final class ShelfEditorWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isForeignTextFocused, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    /// True when a text view other than the annotation canvas's own inline
    /// field is first responder (the canvas field reports through the session).
    private var isForeignTextFocused: Bool {
        guard let textView = firstResponder as? NSTextView, textView.isFieldEditor else {
            return firstResponder is NSTextView
        }
        return !(textView.delegate is NSTextField && (textView.delegate as? NSView)?.superview is AnnotationCanvasView)
    }
}
