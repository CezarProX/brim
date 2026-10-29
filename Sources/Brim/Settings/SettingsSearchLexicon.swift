import Foundation

/// Which Settings panes match a search, by keyword and synonym. Pure data + matching, so it is testable.
enum SettingsSearchLexicon {
  /// Words that live on each pane, besides its title. Keys are the pane titles shown in the sidebar.
  static let keywords: [String: [String]] = [
    "General": ["launch at login", "startup", "dock", "notifications", "sound", "auto close", "screen access", "permissions", "language", "floating thumbnail", "capture preview", "thumbnail corner", "command center", "menu bar", "status icon", "tiles", "layout", "short menu", "stats readout", "song in menu bar", "edit", "pages", "live status", "accessibility", "screen recording", "calendar", "access", "automation", "privacy", "island tour"],
    "Capture & Recording": ["save folder", "format", "png", "jpg", "quality", "file name", "prefix", "date", "auto save", "transparency", "resolution", "upload", "share", "url", "link", "service", "copy link", "server", "screenshot", "capture", "after capture", "floating thumbnail", "thumbnail corner", "sound after capture", "auto close", "share link"],
    "Shortcuts": ["hotkey", "keyboard", "shortcut", "keybinding", "global shortcut", "capture shortcut", "record shortcut"],
    "Island": ["notch click", "hold to reveal", "modifier", "show navigation", "favorites", "pinned", "open size", "enlarged", "hide notch", "black menu bar", "displays", "notch", "hover", "open delay", "collapse", "animation speed", "haptics", "fullscreen", "mission control", "external display", "size", "position", "width", "height", "hide from screen sharing", "right click", "light glass", "progressive blur", "low battery", "low power", "highlight", "window tint", "theme", "color", "colors", "glass", "finish", "clarity", "appearance", "tint", "accent", "text color"],
    "Home & Widgets": ["next event", "second glance", "stats", "cpu", "memory", "ram", "disk", "battery", "network", "weather", "glance", "clock", "temperature", "gpu", "sample interval", "alerts", "calendar", "week starts", "week numbers", "google calendar", "google tasks", "reminders", "things", "to-dos", "today", "pomodoro", "focus", "session color", "end sound", "ambient sound", "auto start", "notes", "apple notes", "obsidian", "vault", "action ring", "ring", "slots", "emoji picker", "emoji", "skin tone", "localsend", "send files", "nearby devices", "mcp", "ai apps", "xcode builds", "stay awake", "caffeine", "keep awake", "schedule", "lid closed", "termi-notch", "terminal", "shell", "teleprompter", "script", "mirror", "text capture", "ocr", "qr code", "barcode", "dropclip", "selected text", "translate", "finder services", "quick actions", "thunderstorm", "launcher", "spotlight", "calculator", "quicklinks", "snippets", "cleaner", "uninstall", "leftovers", "cache cleanup", "menu bar manager", "hidden bar", "thaw", "hide menu bar icons", "claude", "codex", "cursor", "opencode", "ai", "coding", "usage", "meeting", "mute", "camera", "zoom", "teams", "meet", "agent", "per-app volume", "app volume", "remember volumes", "paused apps", "system sounds", "boost", "volume curve", "preferred devices", "output device", "outputs", "microphones", "input", "favorite", "speakers", "headphones", "home", "widgets", "glances", "tools", "library"],
    "Music": ["music", "spotify", "now playing", "lyrics", "artwork", "player", "apple music", "youtube music", "queue", "floating player", "liquid player", "waveform", "visualizer", "swipe", "player buttons", "menu bar song", "incognito", "private browsing", "automix", "lossless", "dolby atmos", "discord", "rich presence", "space bar", "media", "songs"],
    "HUDs & Live Activities": ["volume", "brightness", "keyboard backlight", "bluetooth", "wifi", "offline", "vpn", "drive", "focus mode", "media keys", "system overlay", "level", "placement", "slider color", "quit", "download progress", "dmg", "recording result", "airpods", "notify me", "displays", "capture thumbnail", "caps lock", "full battery", "hotspot", "tethering", "camera in use", "microphone in use", "update available", "charging", "battery", "camera", "microphone", "downloads", "browser", "tabs", "claude code", "codex", "tokens", "current app", "shelf", "basket", "shake", "flashes"],
    "Notifications & Replies": ["notification hud", "banners", "do not disturb", "apps", "alerts in notch", "badges", "reply", "replies", "whatsapp", "telegram", "messages"],
    "Lock Screen": ["lock", "unlock", "clock", "media card", "timer card", "weather", "status row", "look", "liquid", "sounds", "padlock", "screen saver", "artwork scene", "edge sliders", "keep awake after locking"],
    "Clipboard & Tray": ["history", "copy", "paste", "pins", "pinboard", "privacy", "concealed", "passwords", "retention", "limit", "link cleaner", "maccy", "auto clear", "library", "files", "tray", "basket", "drop", "shake", "transform", "convert", "compress", "resize", "zip", "pdf", "trim", "gif", "ocr", "file tray"],
    "About": ["version", "build", "changelog", "release notes", "replay introduction", "tour", "onboarding", "export settings", "import settings", "backup", "logs", "reset", "hard reset", "panel size", "diagnostics", "update"],
  ]


  /// Everyday words that point at technical ones, so "dark" finds Island and "wifi" finds HUDs.
  static let synonyms: [String: [String]] = [
    "dark": ["theme", "color", "appearance"],
    "light": ["theme", "appearance"],
    "sound": ["volume", "sounds"],
    "audio": ["volume", "music", "output"],
    "screenshot": ["capture", "saving", "shortcut"],
    "capture": ["screenshot", "shortcut", "saving"],
    "song": ["music", "now playing", "lyrics"],
    "startup": ["launch at login"],
    "login": ["launch at login"],
    "boot": ["launch at login"],
    "backup": ["export settings", "import settings"],
    "export": ["export settings", "export logs"],
    "import": ["import settings"],
    "bug": ["logs", "diagnostics"],
    "support": ["logs", "diagnostics"],
    "slow": ["animation speed", "cpu"],
    "battery": ["charging"],
    "temp": ["temperature", "weather"],
    "privacy": ["permissions", "concealed"],
    "permission": ["accessibility", "screen recording", "calendar"],
    "hide": ["hidden", "hide from screen sharing"],
    "size": ["width", "height", "panel size"],
    "reset": ["hard reset", "panel size"],
    "tour": ["replay introduction", "onboarding"],
    "intro": ["replay introduction"],
    "menu": ["menu bar", "command center"],
    "tiles": ["command center"],
    "notch": ["island"],
    "dynamic island": ["island", "notch"],
    "wifi": ["network", "vpn"],
    "bluetooth": ["devices"],
    "ai": ["claude", "codex", "agent", "mcp"],
    "sleep": ["stay awake", "keep awake"],
    "caffeinate": ["stay awake"],
    "airdrop": ["localsend"],
    "todo": ["to-dos", "reminders", "things"],
    "tasks": ["to-dos", "reminders", "google tasks"],
    "scan": ["text capture", "qr code"],
    "speaker": ["output device", "outputs"],
    "mic": ["microphones", "microphone"],
  ]

  /// Panes (by title) whose title, keywords or synonyms match every word of `query`. Empty query matches all.
  static func matches(_ query: String, in panes: [String]) -> [String] {
    let words = tokens(query)
    guard !words.isEmpty else { return panes }
    return panes.filter { pane in words.allSatisfy { matches(word: $0, pane: pane) } }
  }

  static func tokens(_ query: String) -> [String] {
    query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty }
  }

  /// Widgets and tools (Home & Widgets drill-ins) whose title or keywords match every word.
  static func matchingTools(_ query: String) -> [SettingsTool] {
    let words = tokens(query)
    guard !words.isEmpty else { return [] }
    return SettingsTool.allCases.filter { tool in
      let haystack = ([tool.title] + tool.keywords).map { $0.lowercased() }
      return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
    }
  }

  private static func matches(word: String, pane: String) -> Bool {
    var haystack = ([pane] + (keywords[pane] ?? [])).map { $0.lowercased() }
    // Home & Widgets also answers to every widget and tool it lists.
    if pane == SettingsPane.widgets.rawValue {
      haystack += SettingsTool.allCases.flatMap { [$0.title] + $0.keywords }.map { $0.lowercased() }
    }
    if haystack.contains(where: { $0.contains(word) }) { return true }
    // A longer word reaches a synonym only through a key of 3+ letters, so "airpods" doesn't expand "ai".
    let expansions = synonyms.filter { $0.key.hasPrefix(word) || ($0.key.count >= 3 && word.hasPrefix($0.key)) }
      .flatMap(\.value)
    return expansions.contains { synonym in haystack.contains { $0.contains(synonym.lowercased()) } }
  }
}
