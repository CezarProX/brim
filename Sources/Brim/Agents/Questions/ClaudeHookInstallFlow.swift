import AppKit

/// The confirm-then-write flow behind the Agents app's "Answer questions" switch and Settings >
/// Agents > "Install Claude Code hook…". Nothing is written until the user presses Install in the
/// dialog, whose "Show details" holds exactly what will be added; the old file is backed up first.
@MainActor
enum ClaudeHookInstallFlow {
  static var executable: String { Bundle.main.executablePath ?? "/Applications/Brim.app/Contents/MacOS/Brim" }
  static var command: String { ClaudeHookSettings.command(executable: executable) }

  /// Installed and pointing at this copy of the app. A hook left by a moved or renamed build counts
  /// as missing, so the Agents app offers to fix it.
  static var isInstalled: Bool {
    ClaudeHookSettings.isInstalled(in: FileManager.default.contents(atPath: ClaudeHookSettings.settingsURL.path), command: command)
  }

  /// The snippet merged into the file, for the confirmation dialog.
  static func preview(existing: Data?, command: String) -> String? {
    guard let result = try? ClaudeHookSettings.merge(existing: nil, command: command), result.changed else { return nil }
    return String(data: result.data, encoding: .utf8)
  }

  /// What the confirmation says: a first install, or re-pointing hooks an older copy left behind.
  static func confirmation(details: String, repointing: Bool) -> BrimDialogContent {
    let backup = BrimDialogContent.Point(
      symbol: "clock.arrow.circlepath",
      text: L10n.tr("Your current settings file is backed up next to it first. Remove the hooks any time in Settings > Agents."))
    if repointing {
      return BrimDialogContent(
        title: L10n.tr("Update Brim’s Claude Code hook?"),
        message: L10n.tr("Claude Code is still set up to ask an older copy of the app, which can’t answer anymore."),
        points: [
          .init(symbol: "arrow.triangle.2.circlepath",
                text: L10n.tr("The two existing Brim hooks are pointed at this copy of Brim. Nothing else changes.")),
          backup,
        ],
        details: details, confirmTitle: L10n.tr("Update"))
    }
    return BrimDialogContent(
      title: L10n.tr("Let Brim answer Claude Code?"),
      message: L10n.tr("Claude Code’s questions and permission requests appear in the notch, so you can answer without going back to the terminal."),
      points: [
        .init(symbol: "bubble.left.and.text.bubble.right",
              text: L10n.tr("Answer questions and choose Allow or Deny right from the island. If Brim isn’t running, Claude Code asks in its terminal as usual.")),
        .init(symbol: "doc.badge.plus",
              text: L10n.tr("Two hooks are added to ~/.claude/settings.json. Everything else in the file stays as it is.")),
        backup,
      ],
      details: details, confirmTitle: L10n.tr("Install"))
  }

  /// Returns true when the file was changed.
  @discardableResult
  static func run() -> Bool {
    let url = ClaudeHookSettings.settingsURL
    let existing = FileManager.default.contents(atPath: url.path)
    let merged: ClaudeHookSettings.Result
    do { merged = try ClaudeHookSettings.merge(existing: existing, command: command) } catch {
      notify(L10n.tr("Brim couldn’t read your Claude Code settings"),
             L10n.tr("~/.claude/settings.json isn’t valid JSON, so Brim left it alone. Fix or remove the file, then try again."))
      return false
    }
    guard merged.changed else {
      notify(L10n.tr("Brim already answers Claude Code"), L10n.tr("Its hooks are already in ~/.claude/settings.json."))
      return false
    }
    let details = preview(existing: existing, command: command) ?? ""
    guard BrimDialog.run(confirmation(details: details, repointing: merged.repointed)) else { return false }
    do {
      let done = try ClaudeHookSettings.install(command: command)
      let saved = done.backup.map { L10n.tr("Your previous settings were saved as %@.", $0.lastPathComponent) }
        ?? L10n.tr("Created ~/.claude/settings.json.")
      notify(L10n.tr("Brim now answers Claude Code"), L10n.tr("New questions from Claude Code appear in the notch.") + " " + saved)
      return true
    } catch {
      notify(L10n.tr("The hooks weren’t installed"), L10n.tr("Nothing in ~/.claude/settings.json was changed.") + " " + error.localizedDescription)
      return false
    }
  }

  /// Removes only Brim's entries, after a backup.
  @discardableResult
  static func remove() -> Bool {
    let url = ClaudeHookSettings.settingsURL
    guard let existing = FileManager.default.contents(atPath: url.path),
      let cleaned = try? ClaudeHookSettings.remove(from: existing)
    else { return false }
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.brim-backup-\(stamp)")
    do {
      try FileManager.default.copyItem(at: url, to: backup)
      try cleaned.write(to: url, options: .atomic)
      return true
    } catch { return false }
  }

  private static func notify(_ title: String, _ message: String) {
    BrimDialog.run(BrimDialogContent(title: title, message: message, cancelTitle: nil))
  }
}
