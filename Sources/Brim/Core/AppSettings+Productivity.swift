import Foundation

/// Typed keys for the Calendar, Pomodoro, Notes, Obsidian and Things surfaces.
extension AppSettings {
  private enum ProductivityKey {
    static let weekStart = "productivity.calendar.weekStart"
    static let weekNumbers = "productivity.calendar.weekNumbers"
    static let pomodoroFocus = "productivity.pomodoro.focusMinutes"
    static let pomodoroBreak = "productivity.pomodoro.breakMinutes"
    static let pomodoroColor = "productivity.pomodoro.color"
    static let pomodoroEndSound = "productivity.pomodoro.endSound"
    static let pomodoroAmbient = "productivity.pomodoro.ambient"
    static let pomodoroFocusHint = "productivity.pomodoro.focusModeHint"
    static let notesBackend = "productivity.notes.backend"
    static let appleNotesSync = "productivity.notes.appleSync"
    static let obsidianVault = "productivity.obsidian.vaultPath"
    static let thingsEnabled = "productivity.things.enabled"
    static let lastDestination = "productivity.calendar.lastDestination"
  }

  /// 0 follows the system; 1...7 is Sunday...Saturday, as `Calendar.firstWeekday`.
  var calendarWeekStart: Int {
    get { min(7, max(0, defaults.integer(forKey: ProductivityKey.weekStart))) }
    set { defaults.set(min(7, max(0, newValue)), forKey: ProductivityKey.weekStart) }
  }

  var calendarWeekNumbers: Bool {
    get { defaults.object(forKey: ProductivityKey.weekNumbers) as? Bool ?? true }
    set { defaults.set(newValue, forKey: ProductivityKey.weekNumbers) }
  }

  var pomodoroFocusMinutes: Int {
    get { defaults.object(forKey: ProductivityKey.pomodoroFocus) as? Int ?? 25 }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroFocus) }
  }

  var pomodoroBreakMinutes: Int {
    get { defaults.object(forKey: ProductivityKey.pomodoroBreak) as? Int ?? 5 }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroBreak) }
  }

  /// A `SessionColor` raw value.
  var pomodoroColorName: String {
    get { defaults.string(forKey: ProductivityKey.pomodoroColor) ?? "orange" }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroColor) }
  }

  /// A `PomodoroEndSound` raw value.
  var pomodoroEndSoundName: String {
    get { defaults.string(forKey: ProductivityKey.pomodoroEndSound) ?? "glass" }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroEndSound) }
  }

  /// An `AmbientSound` raw value.
  var pomodoroAmbientName: String {
    get { defaults.string(forKey: ProductivityKey.pomodoroAmbient) ?? "off" }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroAmbient) }
  }

  var pomodoroFocusModeHint: Bool {
    get { defaults.object(forKey: ProductivityKey.pomodoroFocusHint) as? Bool ?? false }
    set { defaults.set(newValue, forKey: ProductivityKey.pomodoroFocusHint) }
  }

  /// "local" or "obsidian".
  var notesBackendName: String {
    get { defaults.string(forKey: ProductivityKey.notesBackend) ?? "local" }
    set { defaults.set(newValue, forKey: ProductivityKey.notesBackend) }
  }

  var appleNotesSyncEnabled: Bool {
    get { defaults.bool(forKey: ProductivityKey.appleNotesSync) }
    set { defaults.set(newValue, forKey: ProductivityKey.appleNotesSync) }
  }

  var obsidianVaultPath: String? {
    get { defaults.string(forKey: ProductivityKey.obsidianVault) }
    set { defaults.set(newValue, forKey: ProductivityKey.obsidianVault) }
  }

  var thingsBridgeEnabled: Bool {
    get { defaults.bool(forKey: ProductivityKey.thingsEnabled) }
    set { defaults.set(newValue, forKey: ProductivityKey.thingsEnabled) }
  }

  /// The "@" destination last used by quick add, so the next add defaults to it.
  var quickAddLastDestination: String? {
    get { defaults.string(forKey: ProductivityKey.lastDestination) }
    set { defaults.set(newValue, forKey: ProductivityKey.lastDestination) }
  }
}
