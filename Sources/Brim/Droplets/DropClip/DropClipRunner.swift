// DropClipRunner.swift
// Brim
//
// Executes a DropClip action on the selected text and reports what happened.

import AppKit
import CoreServices

struct DropClipOutcome: Equatable {
  /// Short heading for the result strip ("Definition", "Copied" ...).
  var title: String
  /// Text to show, if any.
  var body: String?
  /// What the Copy button on the strip copies.
  var copyable: String?
  var symbol: String
  var isError = false
}

@MainActor
enum DropClipRunner {
  static func run(_ action: DropClipAction, text: String, settings: AppSettings = .shared) async -> DropClipOutcome? {
    switch action {
    case .copy:
      copy(text)
      return DropClipOutcome(title: "Copied", body: nil, copyable: nil, symbol: "checkmark")
    case .search:
      guard let url = DropClipTransforms.expand(template: settings.dropClipSearchTemplate, text: text) else {
        return failure("The search address in settings isn’t valid.")
      }
      NSWorkspace.shared.open(url)
      return DropClipOutcome(title: "Searching", body: nil, copyable: nil, symbol: "magnifyingglass")
    case .define: return define(text)
    case .uppercase: return transformed(DropClipTransforms.uppercased(text), "UPPERCASE")
    case .lowercase: return transformed(DropClipTransforms.lowercased(text), "lowercase")
    case .titleCase: return transformed(DropClipTransforms.titleCased(text), "Title Case")
    case .count:
      let summary = DropClipTransforms.counts(text).summary
      return DropClipOutcome(title: "Count", body: summary, copyable: summary, symbol: "number")
    case .notes: return await sendToNotes(text)
    case .pinboard: return await pin(text)
    case .translate: return nil  // handled by the bar (on-device Translation session)
    case .custom(let id):
      guard let custom = settings.dropClipCustomActions.first(where: { $0.id == id }) else { return failure("That action was removed.") }
      return await runCustom(custom, text: text)
    }
  }

  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private static func failure(_ message: String) -> DropClipOutcome {
    DropClipOutcome(title: message, body: nil, copyable: nil, symbol: "exclamationmark.triangle", isError: true)
  }

  private static func transformed(_ result: String, _ title: String) -> DropClipOutcome {
    copy(result)
    return DropClipOutcome(title: "\(title) · copied", body: result, copyable: result, symbol: "checkmark")
  }

  /// Uses the system Dictionary (Dictionary Services); opens Dictionary.app if there is no entry.
  private static func define(_ text: String) -> DropClipOutcome {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let range = CFRange(location: 0, length: (term as NSString).length)
    if let definition = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String? {
      return DropClipOutcome(title: "Definition", body: definition, copyable: definition, symbol: "character.book.closed")
    }
    if let url = URL(string: "dict://" + DropClipTransforms.escapeForURL(term)) { NSWorkspace.shared.open(url) }
    return DropClipOutcome(title: "No entry found. Opened Dictionary.", body: nil, copyable: nil, symbol: "character.book.closed")
  }

  private static func sendToNotes(_ text: String) async -> DropClipOutcome {
    let source = DropClipTransforms.notesScript(for: text)
    return await Task.detached(priority: .userInitiated) { () -> DropClipOutcome in
      var error: NSDictionary?
      NSAppleScript(source: source)?.executeAndReturnError(&error)
      if let error {
        let message = (error[NSAppleScript.errorMessage] as? String) ?? "Notes didn’t respond."
        return DropClipOutcome(title: "Couldn’t add to Notes", body: message, copyable: nil, symbol: "exclamationmark.triangle", isError: true)
      }
      return DropClipOutcome(title: "Added to Notes", body: nil, copyable: nil, symbol: "note.text")
    }.value
  }

  private static func pin(_ text: String) async -> DropClipOutcome {
    let store = ClipboardStore.shared
    copy(text)
    if store.isMonitoring { await store.captureChange() }
    if let entry = store.entries.first(where: { $0.text == text }), store.setPinned(entry, true) {
      return DropClipOutcome(title: "Pinned to clipboard", body: nil, copyable: nil, symbol: "pin.fill")
    }
    return DropClipOutcome(title: "Copied. Turn on the clipboard history to pin it.", body: nil, copyable: nil, symbol: "pin")
  }

  // MARK: Custom actions

  private static func runCustom(_ custom: DropClipCustomAction, text: String) async -> DropClipOutcome? {
    switch custom.kind {
    case .url:
      guard let url = DropClipTransforms.expand(template: custom.template, text: text) else {
        return failure("“\(custom.title)” has an invalid address template.")
      }
      NSWorkspace.shared.open(url)
      return DropClipOutcome(title: custom.title, body: nil, copyable: nil, symbol: "arrow.up.forward.app")
    case .shell:
      guard confirmShell(custom, text: text) else { return nil }
      return await ShellSnippetRunner.run(custom.template, text: text, title: custom.title)
    }
  }

  /// Every shell snippet run is confirmed, showing exactly what will execute.
  private static func confirmShell(_ custom: DropClipCustomAction, text: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Run “\(custom.title)”?"
    alert.informativeText = "This shell command will run with your selection (\(text.count) characters) in $DROPCLIP_TEXT and on standard input:\n\n\(custom.template)"
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("Run"))
    alert.addButton(withTitle: L10n.tr("Cancel"))
    return alert.runModal() == .alertFirstButtonReturn
  }
}

enum ShellSnippetRunner {
  static let timeout: TimeInterval = 15
  static let maxOutput = 64 * 1024

  /// The text is never interpolated into the command line, so it can't inject shell syntax.
  static func run(_ snippet: String, text: String, title: String) async -> DropClipOutcome {
    await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-c", snippet]
      var environment = ProcessInfo.processInfo.environment
      environment["DROPCLIP_TEXT"] = String(text.prefix(100_000))
      process.environment = environment
      let input = Pipe(), output = Pipe()
      process.standardInput = input
      process.standardOutput = output
      process.standardError = output
      do { try process.run() } catch {
        return DropClipOutcome(title: "Couldn’t run “\(title)”", body: error.localizedDescription, copyable: nil, symbol: "exclamationmark.triangle", isError: true)
      }
      input.fileHandleForWriting.write(Data(text.utf8.prefix(100_000)))
      try? input.fileHandleForWriting.close()
      let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
      let data = output.fileHandleForReading.readData(ofLength: maxOutput)
      process.waitUntilExit()
      killer.cancel()
      let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      let ok = process.terminationStatus == 0
      return DropClipOutcome(
        title: ok ? "\(title) · done" : "\(title) · exit \(process.terminationStatus)",
        body: result.isEmpty ? nil : result, copyable: result.isEmpty ? nil : result,
        symbol: ok ? "checkmark" : "exclamationmark.triangle", isError: !ok)
    }.value
  }
}
