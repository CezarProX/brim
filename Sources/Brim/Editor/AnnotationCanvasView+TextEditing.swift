// AnnotationCanvasView+TextEditing.swift
// Brim
//
// Text-tool behavior: clicking with the text tool creates a text annotation
// and immediately begins editing it via a borderless, transparent-bg
// NSTextField overlaid as a subview. Enter or focus loss commits the text
// into the annotation (an empty result removes the annotation). Clicking an
// existing text annotation with the text tool re-opens it for editing.

import AppKit

extension AnnotationCanvasView: NSTextFieldDelegate {

    func handleTextToolMouseDown(at point: CGPoint) {
        if let hit = hitTestTextAnnotation(at: point) {
            beginEditingText(annotation: hit)
        } else {
            let annotation = Annotation(
                tool: .text,
                rect: CGRect(origin: point, size: .zero),
                text: "",
                style: session.currentStyle
            )
            session.addAnnotation(annotation)
            beginEditingText(annotation: annotation)
        }
    }

    private func hitTestTextAnnotation(at point: CGPoint) -> Annotation? {
        guard let hit = hitTestAnnotation(at: point), hit.tool == .text else { return nil }
        return hit
    }

    func beginEditingText(annotation: Annotation) {
        // Only one inline editor at a time; commit any prior one first.
        if editingAnnotationID != nil {
            commitTextEditing()
        }

        editingAnnotationID = annotation.id
        session.setIsEditingText(true)

        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .medium)
        let width: CGFloat = 260
        let height = annotation.style.fontSize * 1.5
        // NSTextField draws its own text baseline slightly above its frame
        // origin; nudge down so the caret lands near the click point.
        let origin = CGPoint(x: annotation.rect.origin.x, y: annotation.rect.origin.y - height * 0.25)

        let field = NSTextField(frame: CGRect(origin: origin, size: CGSize(width: width, height: height)))
        field.font = font
        field.textColor = annotation.style.color
        field.stringValue = annotation.text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        needsDisplay = true
    }

    func commitTextEditing() {
        guard let id = editingAnnotationID, let field = textField else { return }
        let newText = field.stringValue

        field.delegate = nil
        field.removeFromSuperview()
        textField = nil
        editingAnnotationID = nil
        session.setIsEditingText(false)

        if newText.isEmpty {
            session.removeAnnotation(id: id)
        } else if let existing = session.document.annotations.first(where: { $0.id == id }) {
            session.updateAnnotation(existing.with(text: newText))
        }

        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditing()
            return true
        }
        return false
    }
}
