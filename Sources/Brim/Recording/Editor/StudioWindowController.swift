// StudioWindowController.swift
// Brim
//
// Hosts a Studio editor window per project. Opened when a recording stops, and from
// "Open Recording…" for earlier projects.

import AppKit
import SwiftUI

@MainActor
final class StudioWindowController: NSWindowController, NSWindowDelegate {
    static var open: [StudioWindowController] = []

    let model: StudioModel

    init(model: StudioModel) {
        self.model = model
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = model.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(StudioTheme.window)
        window.minSize = CGSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StudioView(model: model))
        window.center()
        window.setFrameAutosaveName("BrimStudio")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    static func open(project: RecordingProject) {
        if let existing = open.first(where: { $0.model.project == project }) {
            existing.present()
            return
        }
        do {
            let model = try StudioModel(project: project)
            let controller = StudioWindowController(model: model)
            open.append(controller)
            controller.present()
        } catch {
            IslandFlashCenter.shared.show(L10n.tr("Couldn't open the recording"), symbol: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    /// "Open Recording…": choose a saved project from the Recordings folder.
    static func chooseProject() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = L10n.tr("Choose a recording to keep editing in Studio.")
        panel.directoryURL = RecordingLibrary.root
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == RecordingProject.folderExtension else { return }
        open(project: RecordingProject(folder: url))
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        model.loadThumbnails()
        model.refreshStill()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelExport()
        model.tearDownPlayer()
        model.saveNow()
        Self.open.removeAll { $0 === self }
    }
}
