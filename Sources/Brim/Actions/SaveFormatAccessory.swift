// SaveFormatAccessory.swift
// Brim
//
// The small "Format: [PNG ▾]" accessory view shown in the save panel, which
// keeps the panel's name field extension and allowed content type in sync
// with the selected format.

import AppKit
import UniformTypeIdentifiers

/// Owns the accessory view for `NSSavePanel` that lets the user pick PNG or
/// JPEG, updating the panel's file name extension and allowed content types
/// to match.
@MainActor
final class SaveFormatAccessory: NSObject {

    private(set) var selectedFormat: ImageEncoder.Format
    let view: NSView

    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var panel: NSSavePanel?
    private let baseName: String

    init(panel: NSSavePanel, baseName: String, initialFormat: ImageEncoder.Format) {
        self.panel = panel
        self.baseName = baseName
        self.selectedFormat = initialFormat

        let label = NSTextField(labelWithString: "Format:")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        container.addSubview(label)
        container.addSubview(popUpButton)
        self.view = container

        super.init()

        popUpButton.addItem(withTitle: L10n.tr("PNG"))
        popUpButton.addItem(withTitle: L10n.tr("JPEG"))
        popUpButton.selectItem(at: initialFormat == .png ? 0 : 1)
        popUpButton.target = self
        popUpButton.action = #selector(formatChanged)

        layout(label: label, popUp: popUpButton, in: container)
        applyFormat(initialFormat)
    }

    private func layout(label: NSTextField, popUp: NSPopUpButton, in container: NSView) {
        label.translatesAutoresizingMaskIntoConstraints = false
        popUp.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            popUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popUp.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            popUp.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
    }

    @objc private func formatChanged() {
        let format: ImageEncoder.Format = popUpButton.indexOfSelectedItem == 0 ? .png : .jpg
        selectedFormat = format
        applyFormat(format)
    }

    private func applyFormat(_ format: ImageEncoder.Format) {
        panel?.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        switch format {
        case .png:
            panel?.allowedContentTypes = [.png]
        case .jpg:
            panel?.allowedContentTypes = [.jpeg]
        }
    }
}
