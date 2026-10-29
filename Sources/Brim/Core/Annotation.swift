// Annotation.swift
// Brim
//
// The annotation data model used by the editing toolbar (owned by
// agent-editor). This is a shared contract: fully implemented here (not a
// stub) since other modules depend on its exact shape.
//
// Design notes:
//  - `Annotation` is a value type; all "mutation" is done via `with(...)`
//    helpers that return a modified copy (project convention: prefer
//    immutable updates over in-place mutation).
//  - `AnnotationDocument` holds the live list of annotations for a capture
//    session plus undo/redo history. The undo model is intentionally simple:
//    it snapshots the entire `annotations` array on every change rather than
//    computing per-operation diffs. This is easy to reason about and more
//    than fast enough for the small annotation counts a screenshot editor
//    deals with.

import AppKit

/// The drawing tools available in the annotation toolbar.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case pen
    case line
    case arrow
    case rectangle
    case highlighter
    case text
    /// A quadratic arrow: `points` = [start, control, end].
    case curvedArrow
    case ellipse
    /// Frosted region over the screenshot (`rect`).
    case blur
    /// Blocky mosaic over the screenshot (`rect`).
    case pixelate
    /// Dims everything outside `rect`; several spotlights share one veil.
    case spotlight
    /// A round lens over `rect` showing the pixels underneath at 2x.
    case magnifier
    /// A numbered step badge centred in `rect`; the number lives in `text`.
    case counter
    /// Non-destructive crop of the whole image (`rect`, image points). At most
    /// one per document; never drawn as a mark, never hit-tested.
    case crop
}

/// Visual styling applied to a single annotation.
public struct AnnotationStyle: Sendable {
    public var color: NSColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    /// Rectangles and ellipses fill with `color` instead of stroking it.
    public var isFilled: Bool

    public init(
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 3.0,
        fontSize: CGFloat = 18.0,
        isFilled: Bool = false
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.isFilled = isFilled
    }
}

/// A single annotation placed on the capture canvas.
///
/// Not every field is meaningful for every tool:
///  - `pen` / `highlighter` use `points` (a freehand stroke path).
///  - `line` / `arrow` use `points` with exactly two elements (start, end).
///  - `rectangle` uses `rect`.
///  - `text` uses `rect` (bounding box / insertion point) and `text`.
///  - `curvedArrow` uses `points` = [start, control, end].
///  - `ellipse`, `blur`, `pixelate`, `spotlight`, `magnifier`, `crop` use `rect`.
///  - `counter` uses `rect` (badge bounds) and `text` (its step number).
public struct Annotation: Identifiable, Sendable {
    public let id: UUID
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var rect: CGRect
    public var text: String
    public var style: AnnotationStyle

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [CGPoint] = [],
        rect: CGRect = .zero,
        text: String = "",
        style: AnnotationStyle = AnnotationStyle()
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.rect = rect
        self.text = text
        self.style = style
    }

    /// Returns a copy of this annotation with `points` replaced.
    public func with(points: [CGPoint]) -> Annotation {
        var copy = self
        copy.points = points
        return copy
    }

    /// Returns a copy of this annotation with `rect` replaced.
    public func with(rect: CGRect) -> Annotation {
        var copy = self
        copy.rect = rect
        return copy
    }

    /// Returns a copy of this annotation with `text` replaced.
    public func with(text: String) -> Annotation {
        var copy = self
        copy.text = text
        return copy
    }

    /// Returns a copy of this annotation with `style` replaced.
    public func with(style: AnnotationStyle) -> Annotation {
        var copy = self
        copy.style = style
        return copy
    }
}

/// The mutable set of annotations for one capture/editing session, with
/// linear undo/redo history.
///
/// Undo model: every mutating call pushes the *previous* state of
/// `annotations` onto `undoStack` before applying the change, and clears
/// `redoStack` (standard "new edit invalidates redo future" behavior).
/// `undo()` / `redo()` swap the current array with the top of the
/// appropriate stack, pushing onto the other stack so the operation is
/// reversible.
public struct AnnotationDocument {
    public private(set) var annotations: [Annotation]
    private var undoStack: [[Annotation]]
    private var redoStack: [[Annotation]]

    public init(annotations: [Annotation] = []) {
        self.annotations = annotations
        self.undoStack = []
        self.redoStack = []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Adds a new annotation.
    public mutating func add(_ annotation: Annotation) {
        pushUndoSnapshot()
        annotations.append(annotation)
    }

    /// Replaces the existing annotation with the same `id`. No-op (and no
    /// undo snapshot pushed) if no annotation with that id exists.
    public mutating func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }
        pushUndoSnapshot()
        annotations[index] = annotation
    }

    /// Removes the annotation with the given `id`, if present.
    public mutating func remove(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        annotations.removeAll { $0.id == id }
    }

    /// Removes all annotations.
    public mutating func clear() {
        guard !annotations.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeAll()
    }

    /// Reverts to the previous snapshot, if any.
    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    /// Re-applies a snapshot previously undone, if any.
    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private mutating func pushUndoSnapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}
