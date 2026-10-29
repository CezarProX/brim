import Foundation

/// One step of the scripted demo used to film the launch video (`Brim --demo`, see `DemoController`).
/// Commands arrive as plain text such as `open home`, `flash volume 60` or `tray add /path/file.png`.
enum DemoCommand: Equatable {
  enum Flash: Equatable {
    case volume(Double)
    case capsLock(Bool)
    case charging(Int)
    case full
    case unplugged(Int)
    case airPods
    case camera
    case microphone
  }

  /// For the session: keeps the island with a hidden menu bar and ignores the filming tool's screen recording.
  case prepare
  /// Puts back what `prepare` changed and closes everything the demo opened.
  case finish
  case open(IslandPage)
  case widget(IslandWidgetTile)
  case close
  case customize(Bool)
  /// Draws the built-in display's island as a floating Dynamic Island pill, as on a notchless display.
  case pill(Bool)
  case flash(Flash)
  case trayAdd([URL])
  case trayClear
  /// Opens a floating Basket at a screen point (AppKit coordinates, origin bottom-left) holding files.
  case basket(CGPoint, [URL])
  case basketClose
  /// The quick-action tiles a shake brings up (Drop, Transform, AirDrop…), beside a screen point.
  case quickActions(CGPoint)
  case quickActionsClose
  /// A Messages notification from a made-up contact (`message Alex Morgan: Nachos at seven?`).
  case message(sender: String, body: String)
  /// Types into the notification's reply field, one character at a time.
  case type(String)
  /// Sends the typed reply (to a pretend transport: nothing leaves the Mac).
  case send
  case ring(CGPoint)
  case ringClose
  /// The post-capture thumbnail for an image file, as if it had just been captured (nothing is copied).
  case thumbnail(URL)
  /// Shows or hides the thumbnail's hover controls, as when the pointer rests on it.
  case thumbnailHover(Bool)
  case thumbnailClose
  /// The "Edit screenshot" window on an image file; `mark` draws into it.
  case editorOpen(URL)
  case editorClose
  case mark(Mark)

  /// An annotation drawn into the demo editor, in the image's points with the origin at the top left.
  enum Mark: Equatable {
    case ellipse(CGRect)
    case arrow(CGPoint, CGPoint)
    case text(CGPoint, String)
  }

  static func parse(_ text: String) -> DemoCommand? {
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let verb = words.first?.lowercased() else { return nil }
    let args = Array(words.dropFirst())
    switch verb {
    case "prepare": return args.isEmpty ? .prepare : nil
    case "finish": return args.isEmpty ? .finish : nil
    case "close": return args.isEmpty ? .close : nil
    case "open": return args.count == 1 ? page(args[0]).map(DemoCommand.open) : nil
    case "widget": return args.count == 1 ? IslandWidgetTile(rawValue: args[0]).map(DemoCommand.widget) : nil
    case "customize": return toggle(args).map(DemoCommand.customize)
    case "pill": return toggle(args).map(DemoCommand.pill)
    case "flash": return flash(args).map(DemoCommand.flash)
    case "tray": return tray(args, rest: rest(of: text, after: 2))
    case "basket":
      if args == ["close"] { return .basketClose }
      guard args.count >= 3, let point = point(args[0], args[1]), let url = fileURL(rest(of: text, after: 3)) else { return nil }
      return .basket(point, [url])
    case "message":
      let text = rest(of: text, after: 1)
      guard let colon = text.firstIndex(of: ":") else { return nil }
      let sender = text[..<colon].trimmingCharacters(in: .whitespaces)
      let body = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      return sender.isEmpty || body.isEmpty ? nil : .message(sender: sender, body: body)
    case "type":
      let typed = rest(of: text, after: 1)
      return typed.isEmpty ? nil : .type(typed)
    case "send": return args.isEmpty ? .send : nil
    case "quickactions":
      if args == ["close"] { return .quickActionsClose }
      guard args.count == 2, let point = point(args[0], args[1]) else { return nil }
      return .quickActions(point)
    case "ring":
      if args == ["close"] { return .ringClose }
      guard args.count == 2, let point = point(args[0], args[1]) else { return nil }
      return .ring(point)
    case "thumb": return thumbnail(args, rest: rest(of: text, after: 2))
    case "editor": return editor(args, rest: rest(of: text, after: 2))
    default: return nil
    }
  }

  private static func thumbnail(_ args: [String], rest path: String) -> DemoCommand? {
    switch args.first?.lowercased() {
    case "show": return fileURL(path).map(DemoCommand.thumbnail)
    case "hover": return toggle(Array(args.dropFirst())).map(DemoCommand.thumbnailHover)
    case "close": return args.count == 1 ? .thumbnailClose : nil
    default: return nil
    }
  }

  private static func editor(_ args: [String], rest: String) -> DemoCommand? {
    let numbers = args.dropFirst().prefix(4).compactMap(Double.init)
    switch args.first?.lowercased() {
    case "open": return fileURL(rest).map(DemoCommand.editorOpen)
    case "close": return args.count == 1 ? .editorClose : nil
    case "ellipse":
      guard args.count == 5, numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
      return .mark(.ellipse(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])))
    case "arrow":
      guard args.count == 5, numbers.count == 4 else { return nil }
      return .mark(.arrow(CGPoint(x: numbers[0], y: numbers[1]), CGPoint(x: numbers[2], y: numbers[3])))
    case "text":
      guard args.count >= 4, let at = point(args[1], args[2]) else { return nil }
      return .mark(.text(at, Self.rest(of: rest, after: 2)))
    default: return nil
    }
  }

  private static func page(_ name: String) -> IslandPage? {
    switch name.lowercased() {
    case "home": .home
    case "clipboard": .clipboard
    case "tray": .tray
    case "music": .music
    case "widgets": .widgets
    case "messages": .messages
    default: nil
    }
  }

  private static func toggle(_ args: [String]) -> Bool? {
    guard args.count == 1 else { return nil }
    switch args[0].lowercased() {
    case "on": return true
    case "off": return false
    default: return nil
    }
  }

  private static func flash(_ args: [String]) -> Flash? {
    guard let kind = args.first?.lowercased() else { return nil }
    let rest = Array(args.dropFirst())
    let percent = rest.count == 1 ? Int(rest[0]).map { min(100, max(0, $0)) } : nil
    switch kind {
    case "volume": return percent.map { .volume(Double($0) / 100) }
    case "caps": return toggle(rest).map(Flash.capsLock)
    case "charging": return percent.map(Flash.charging)
    case "unplugged": return percent.map(Flash.unplugged)
    case "full": return rest.isEmpty ? .full : nil
    case "airpods": return rest.isEmpty ? .airPods : nil
    case "camera": return rest.isEmpty ? .camera : nil
    case "mic": return rest.isEmpty ? .microphone : nil
    default: return nil
    }
  }

  private static func tray(_ args: [String], rest path: String) -> DemoCommand? {
    switch args.first?.lowercased() {
    case "clear": return args.count == 1 ? .trayClear : nil
    case "add": return fileURL(path).map { .trayAdd([$0]) }
    default: return nil
    }
  }

  private static func point(_ x: String, _ y: String) -> CGPoint? {
    guard let x = Double(x), let y = Double(y) else { return nil }
    return CGPoint(x: x, y: y)
  }

  /// Only absolute paths, so a command can never resolve against the app's working directory.
  private static func fileURL(_ path: String) -> URL? {
    guard path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path)
  }

  /// The text after the first `count` words, keeping its inner spaces (file paths may contain them).
  private static func rest(of text: String, after count: Int) -> String {
    var remaining = Substring(text).drop(while: \.isWhitespace)
    for _ in 0..<count {
      remaining = remaining.drop(while: { !$0.isWhitespace }).drop(while: \.isWhitespace)
    }
    return String(remaining).trimmingCharacters(in: .whitespaces)
  }
}
