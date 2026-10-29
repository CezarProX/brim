import Foundation

enum TextCaptureCompletion: String, CaseIterable, Identifiable {
  case showResult, copy, both
  var id: String { rawValue }
  var title: String {
    switch self {
    case .showResult: "Show result"
    case .copy: "Copy to clipboard"
    case .both: "Show result and copy"
    }
  }
  var copies: Bool { self != .showResult }
  var shows: Bool { self != .copy }
}

extension AppSettings {
  var textCaptureEnabled: Bool {
    get { defaults.bool(forKey: "textCaptureEnabled") }
    set { defaults.set(newValue, forKey: "textCaptureEnabled") }
  }
  /// Default: ⌃⌥T.
  var textCaptureShortcut: DropletShortcut {
    get { .load("textCapture", fallback: DropletShortcut(keyCode: 17, modifiers: 6144), from: defaults) }
    set { newValue.save("textCapture", to: defaults) }
  }
  /// "auto" or a Vision language code such as "en-US".
  var textCaptureLanguage: String {
    get { defaults.string(forKey: "textCaptureLanguage") ?? "auto" }
    set { defaults.set(newValue, forKey: "textCaptureLanguage") }
  }
  var textCaptureLanguageCorrection: Bool {
    get { defaults.object(forKey: "textCaptureLanguageCorrection") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "textCaptureLanguageCorrection") }
  }
  var textCaptureCompletion: TextCaptureCompletion {
    get { defaults.string(forKey: "textCaptureCompletion").flatMap(TextCaptureCompletion.init(rawValue:)) ?? .both }
    set { defaults.set(newValue.rawValue, forKey: "textCaptureCompletion") }
  }
  /// Copy a QR code or barcode payload as soon as it is read.
  var textCaptureAutoCopyCodes: Bool {
    get { defaults.bool(forKey: "textCaptureAutoCopyCodes") }
    set { defaults.set(newValue, forKey: "textCaptureAutoCopyCodes") }
  }
  var textCaptureKeepHistory: Bool {
    get { defaults.object(forKey: "textCaptureKeepHistory") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "textCaptureKeepHistory") }
  }
}
