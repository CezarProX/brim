// HistoryWindowController.swift
// Brim
//
// A minimal window that lists recorded `HistoryEntry` records (date, kind,
// pixel size, and a link/path) with double-click to reveal the file in
// Finder or open the link in the default browser.

import AppKit

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    /// Keeps controllers alive while their windows are open (an `NSWindow`
    /// doesn't retain its controller, and we don't want ARC to tear the
    /// window down the instant `showHistoryWindow` returns).
    private static var openControllers: [HistoryWindowController] = []

    private let tableView = NSTableView()
    private var entries: [HistoryEntry]

    private init(kind: HistoryEntry.Kind?) {
        self.entries = HistoryStore.shared.entries(kind: kind)

        let title = Self.title(for: kind)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        configureTableView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HistoryWindowController does not support NSCoder")
    }

    /// Shows a history window listing entries of `kind`, or every entry if
    /// `kind` is `nil`.
    static func showHistoryWindow(kind: HistoryEntry.Kind? = nil) {
        let controller = HistoryWindowController(kind: kind)
        openControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }

    private static func title(for kind: HistoryEntry.Kind?) -> String {
        switch kind {
        case .save: return "Screenshot History"
        case .upload: return "Upload History"
        case .clipboard: return "Clipboard History"
        case nil: return "History"
        }
    }

    // MARK: - Table setup

    private func configureTableView() {
        let scrollView = NSScrollView(frame: window?.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .default
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        let dateColumn = NSTableColumn(identifier: .init("date"))
        dateColumn.title = L10n.tr("Date")
        dateColumn.width = 160
        tableView.addTableColumn(dateColumn)

        let kindColumn = NSTableColumn(identifier: .init("kind"))
        kindColumn.title = L10n.tr("Kind")
        kindColumn.width = 80
        tableView.addTableColumn(kindColumn)

        let sizeColumn = NSTableColumn(identifier: .init("size"))
        sizeColumn.title = L10n.tr("Size")
        sizeColumn.width = 90
        tableView.addTableColumn(sizeColumn)

        let locationColumn = NSTableColumn(identifier: .init("location"))
        locationColumn.title = L10n.tr("Location")
        locationColumn.width = 210
        tableView.addTableColumn(locationColumn)

        window?.contentView = scrollView
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, entries.indices.contains(row) else { return nil }
        let entry = entries[row]

        let text: String
        switch identifier.rawValue {
        case "date":
            text = Self.dateFormatter.string(from: entry.date)
        case "kind":
            text = entry.kind.rawValue.capitalized
        case "size":
            text = entry.pixelSize
        case "location":
            text = entry.link?.absoluteString ?? entry.fileURL?.path ?? "—"
        default:
            text = ""
        }

        let cellIdentifier = NSUserInterfaceItemIdentifier("cell")
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField {
            textField = reused
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = .systemFont(ofSize: 12)
        }
        textField.stringValue = text
        return textField
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard entries.indices.contains(row) else { return }
        let entry = entries[row]

        if let link = entry.link {
            NSWorkspace.shared.open(link)
        } else if let fileURL = entry.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
