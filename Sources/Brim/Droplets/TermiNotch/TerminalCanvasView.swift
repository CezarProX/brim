// TerminalCanvasView.swift
// Brim
//
// Draws a TerminalBuffer in a SwiftUI Canvas and turns key presses / scrolling into PTY input.

import AppKit
import SwiftUI

enum TerminalPalette {
  /// Soft, readable 16 colors tuned for a black island.
  static let ansi: [Color] = [
    Color(white: 0.16), Color(red: 1.0, green: 0.38, blue: 0.36), Color(red: 0.36, green: 0.84, blue: 0.47),
    Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.42, green: 0.62, blue: 1.0),
    Color(red: 0.84, green: 0.52, blue: 0.98), Color(red: 0.38, green: 0.84, blue: 0.86), Color(white: 0.82),
    Color(white: 0.42), Color(red: 1.0, green: 0.52, blue: 0.50), Color(red: 0.52, green: 0.92, blue: 0.62),
    Color(red: 1.0, green: 0.90, blue: 0.52), Color(red: 0.58, green: 0.74, blue: 1.0),
    Color(red: 0.92, green: 0.68, blue: 1.0), Color(red: 0.56, green: 0.92, blue: 0.94), .white,
  ]
  static let defaultForeground = Color(white: 0.92)

  static func color(_ color: TerminalColor) -> Color? {
    switch color {
    case .standard: return nil
    case .rgb(let r, let g, let b): return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    case .palette(let index):
      switch index {
      case 0..<16: return ansi[index]
      case 16..<232:
        let n = index - 16
        let level = { (v: Int) in v == 0 ? 0.0 : Double(55 + v * 40) / 255 }
        return Color(red: level(n / 36), green: level((n / 6) % 6), blue: level(n % 6))
      default:
        let value = Double(8 + (index - 232) * 10) / 255
        return Color(white: value)
      }
    }
  }
}

struct TerminalCanvasView: View {
  @ObservedObject var session: TerminalSession
  let fontSize: CGFloat
  @State private var scrollLines = 0
  @FocusState private var focused: Bool

  private var cell: CGSize {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    return CGSize(width: ceil("M".size(withAttributes: [.font: font]).width), height: ceil(fontSize * 1.32))
  }

  var body: some View {
    GeometryReader { proxy in
      let columns = max(20, Int((proxy.size.width - 16) / cell.width))
      let rows = max(2, Int((proxy.size.height - 10) / cell.height))
      ZStack {
        Canvas { context, _ in draw(&context, rows: rows) }
          .padding(.horizontal, 8).padding(.vertical, 5)
        TerminalKeyCatcher(
          onText: { scrollLines = 0; session.send($0) },
          onScroll: { delta in
            let maxScroll = session.buffer.scrollback.count
            scrollLines = min(maxScroll, max(0, scrollLines + delta))
          },
          onCopy: { copyScreen() },
          onClear: { session.clearOutput() },
          onPaste: { scrollLines = 0; session.paste($0) })
        if let failure = session.failure {
          Text(failure).font(IslandFont.body).foregroundStyle(IslandInk.secondary)
        } else if !session.isAlive && !session.buffer.screenText.isEmpty {
          VStack { Spacer(); Text("The shell ended. Close this tab, or press + for a new one.")
            .font(IslandFont.caption).foregroundStyle(IslandInk.secondary).padding(.bottom, 6) }
        }
      }
      .onAppear { session.resize(columns: columns, rows: rows) }
      .onChange(of: columns) { _, _ in session.resize(columns: columns, rows: rows) }
      .onChange(of: rows) { _, _ in session.resize(columns: columns, rows: rows) }
    }
  }

  private func draw(_ context: inout GraphicsContext, rows visibleRows: Int) {
    let buffer = session.buffer
    let lines = buffer.allLines
    let end = max(0, lines.count - scrollLines)
    let start = max(0, end - visibleRows)
    let cellSize = cell
    let font = Font.system(size: fontSize, design: .monospaced)
    for (offset, index) in (start..<end).enumerated() {
      let y = CGFloat(offset) * cellSize.height
      drawLine(&context, lines[index], y: y, cell: cellSize, font: font,
               cursorColumn: scrollLines == 0 && index == lines.count - buffer.rows + buffer.cursorRow && buffer.cursorVisible ? buffer.cursorColumn : nil)
    }
  }

  private func drawLine(_ context: inout GraphicsContext, _ line: [TerminalCell], y: CGFloat, cell: CGSize, font: Font, cursorColumn: Int?) {
    var runStart = 0
    while runStart < line.count {
      let style = line[runStart].style
      var runEnd = runStart + 1
      if runStart != cursorColumn {
        while runEnd < line.count, runEnd != cursorColumn, line[runEnd].style == style { runEnd += 1 }
      }
      drawRun(&context, line[runStart..<runEnd], style: style, x: CGFloat(runStart) * cell.width, y: y, cell: cell, font: font,
              cursor: runStart == cursorColumn)
      runStart = runEnd
    }
  }

  private func drawRun(_ context: inout GraphicsContext, _ cells: ArraySlice<TerminalCell>, style: TerminalStyle, x: CGFloat, y: CGFloat, cell: CGSize, font: Font, cursor: Bool) {
    var foreground: Color = TerminalPalette.color(style.foreground) ?? TerminalPalette.defaultForeground
    var background: Color? = TerminalPalette.color(style.background)
    if style.inverse {
      let previous = foreground
      foreground = background ?? .black
      background = previous
    }
    if cursor {
      background = TerminalPalette.defaultForeground
      foreground = .black
    }
    let width = CGFloat(cells.count) * cell.width
    if let background { context.fill(Path(CGRect(x: x, y: y, width: width, height: cell.height)), with: .color(background)) }
    let text = String(cells.map(\.character))
    guard !text.allSatisfy({ $0 == " " }) else { return }
    var styled = Text(text).font(style.bold ? font.bold() : font).foregroundColor(style.dim ? foreground.opacity(0.6) : foreground)
    if style.italic { styled = styled.italic() }
    if style.underline { styled = styled.underline() }
    context.draw(context.resolve(styled), at: CGPoint(x: x, y: y + cell.height / 2), anchor: .leading)
  }

  private func copyScreen() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(session.outputText, forType: .string)
  }
}

// MARK: - Keyboard

struct TerminalKeyCatcher: NSViewRepresentable {
  var onText: (String) -> Void
  var onScroll: (Int) -> Void
  var onCopy: () -> Void
  var onClear: () -> Void
  var onPaste: (String) -> Void

  func makeNSView(context: Context) -> KeyView {
    let view = KeyView()
    update(view)
    DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    return view
  }

  func updateNSView(_ view: KeyView, context: Context) { update(view) }

  private func update(_ view: KeyView) {
    view.onText = onText
    view.onScroll = onScroll
    view.onCopy = onCopy
    view.onClear = onClear
    view.onPaste = onPaste
  }

  final class KeyView: NSView {
    var onText: ((String) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onCopy: (() -> Void)?
    var onClear: (() -> Void)?
    var onPaste: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func scrollWheel(with event: NSEvent) {
      let lines = Int((event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 8 : 1)).rounded())
      if lines != 0 { onScroll?(lines) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers else { return false }
      switch key {
      case "v":
        if let text = NSPasteboard.general.string(forType: .string) { onPaste?(text) }
        return true
      case "c": onCopy?(); return true
      case "k": onClear?(); return true
      case "t": Task { @MainActor in TermiNotchModel.shared.newTab() }; return true
      case "w":
        Task { @MainActor in if let tab = TermiNotchModel.shared.selected { TermiNotchModel.shared.close(tab) } }
        return true
      default: return false
      }
    }

    override func keyDown(with event: NSEvent) {
      let flags = event.modifierFlags
      guard !flags.contains(.command) else { return }
      guard let bytes = TerminalKeyEncoder.bytes(
        characters: event.characters ?? "", charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
        keyCode: event.keyCode, control: flags.contains(.control), option: flags.contains(.option))
      else { return }
      onText?(bytes)
    }
  }
}
