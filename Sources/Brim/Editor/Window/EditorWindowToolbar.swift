// EditorWindowToolbar.swift
// Brim
//
// The editor window's title-bar row: sidebar toggle and title on the left,
// the system share button and a "Done" pill on the right.

import AppKit

@MainActor
final class EditorWindowToolbar: NSObject, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate {
    var onToggleSidebar: (() -> Void)?
    var onDone: (() -> Void)?
    var shareItems: (() -> [Any])?

    private static let sidebar = NSToolbarItem.Identifier("qs.editor.sidebar")
    private static let title = NSToolbarItem.Identifier("qs.editor.title")
    private static let share = NSToolbarItem.Identifier("qs.editor.share")
    private static let done = NSToolbarItem.Identifier("qs.editor.done")

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "qs.editor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebar, Self.title, .flexibleSpace, Self.share, Self.done]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.sidebar:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L10n.tr("Toggle sidebar"))
            item.label = L10n.tr("Toggle sidebar")
            item.toolTip = L10n.tr("Toggle sidebar")
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleSidebar)
            return item
        case Self.title:
            let label = NSTextField(labelWithString: L10n.tr("Edit screenshot"))
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = label
            return item
        case Self.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.delegate = self
            item.toolTip = L10n.tr("Share")
            return item
        case Self.done:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = makeDoneButton()
            item.label = L10n.tr("Done")
            return item
        default:
            return nil
        }
    }

    private func makeDoneButton() -> NSButton {
        let button = EditorDoneButton(title: L10n.tr("Done"), target: self, action: #selector(done))
        button.toolTip = L10n.tr("Apply and save to the shelf (⌘↩)")
        return button
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        shareItems?() ?? []
    }

    @objc private func toggleSidebar() { onToggleSidebar?() }
    @objc private func done() { onDone?() }
}

/// The accent "✓ Done" pill. Drawn by hand so it keeps its colour whether
/// or not the window is key (a tinted push button greys out when inactive).
@MainActor
final class EditorDoneButton: NSButton {
    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 84, height: 28))
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setAccessibilityLabel(title)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: intrinsicContentSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.size().width) + 46, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.controlAccentColor.blended(withFraction: isHighlighted ? 0.2 : 0, of: .black)?.setFill()
        pill.fill()
        let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        let textSize = label.size()
        let total = 14 + 6 + textSize.width
        var x = bounds.midX - total / 2
        if let check, let tinted = check.tinted(.white) {
            tinted.draw(in: CGRect(x: x, y: bounds.midY - 6.5, width: 14, height: 13))
        }
        x += 20
        label.draw(at: CGPoint(x: x, y: bounds.midY - textSize.height / 2))
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        draw(in: CGRect(origin: .zero, size: size))
        color.set()
        CGRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
