import AppKit

/// The macOS Services Brim offers for files selected in Finder: "Add to Brim Tray" and
/// "Transform with Brim". The menu entries are declared under `NSServices` in Info.plist;
/// `NSMessage` names below map to the two `@objc` handlers.
@MainActor
final class FinderServicesProvider: NSObject {
  static let shared = FinderServicesProvider()

  /// Registers this object as the app's services provider. Call once at launch.
  func start() {
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
  }

  /// File URLs on a services pasteboard, in order, without duplicates. Web URLs are ignored.
  nonisolated static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    var seen = Set<String>()
    return objects.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }

  @objc func addToTray(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
    let urls = Self.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Brim found no files to add." as NSString
      return
    }
    // Services run on the main thread; hop explicitly because the handler is called nonisolated by AppKit.
    MainActor.assumeIsolated {
      let added = FileTrayStore.shared.add(urls)
      if added == 0 {
        IslandFlashCenter.shared.show("Already in the tray", symbol: "tray.fill", tint: .white)
      }
    }
  }

  @objc func transformFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
    let urls = Self.fileURLs(from: pasteboard)
    guard !urls.isEmpty else {
      error.pointee = "Brim found no files to transform." as NSString
      return
    }
    MainActor.assumeIsolated { NotchShelfController.shared.presentConvert(urls) }
  }
}
