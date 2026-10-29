import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SharingActivityModel: ObservableObject {
  static let shared = SharingActivityModel()
  @Published private(set) var files: [URL] = []
  @Published private(set) var status = "Drop files here to share"
  @Published var link = ""
  @Published var isPresenting = false
  /// Set when an item could not be added (unreadable, not a file); cleared by the next good add.
  @Published private(set) var notice: String?
  private var importGeneration = 0
  var isActive: Bool { !files.isEmpty }

  func chooseFiles() {
    importGeneration += 1
    let generation = importGeneration
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    isPresenting = true
    panel.begin { [weak self] response in
      MainActor.assumeIsolated {
        self?.isPresenting = false
        if response == .OK, self?.importGeneration == generation { self?.accept(panel.urls) }
      }
    }
  }

  func accept(_ urls: [URL]) {
    let valid = urls.filter {
      guard $0.isFileURL,
        let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isReadableKey]),
        values.isRegularFile == true || values.isDirectory == true, values.isReadable == true
      else { return false }
      return true
    }
    files = Array(Set(files + valid)).sorted { $0.path < $1.path }.prefix(10).map { $0 }
    status =
      valid.isEmpty ? "Choose readable files to share." : "\(files.count) file(s) ready to share"
    notice = valid.count < urls.count ? L10n.tr("Some items could not be read and were skipped.") : nil
  }

  func remove(_ url: URL) {
    files.removeAll { $0 == url }
    if files.isEmpty { clear() }
  }

  /// Hands the files straight to AirDrop (the system picker lists nearby people), no share menu first.
  var airDropAvailable: Bool {
    NSSharingService(named: .sendViaAirDrop)?.canPerform(withItems: files) ?? false
  }

  func airDrop() {
    guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
      notice = L10n.tr("AirDrop is not available. Turn on Wi-Fi and Bluetooth.")
      return
    }
    service.perform(withItems: files)
  }

  func drop(_ providers: [NSItemProvider]) -> Bool {
    importGeneration += 1
    let generation = importGeneration
    return FileDropLoader.load(providers, limit: 10) { [weak self] urls in
      guard let self, self.importGeneration == generation else { return }
      self.accept(urls)
    }
  }

  func clear() {
    importGeneration += 1
    files = []
    notice = nil
    status = "Drop files here to share"
  }

  static func shareableLink(_ value: String) -> URL? {
    guard value.count <= 2048,
      let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  static func qrCode(for value: String) -> NSImage? {
    guard let url = shareableLink(value) else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(url.absoluteString.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
      let image = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: 160, height: 160))
  }
}

struct NativeShareButton: NSViewRepresentable {
  let items: [URL]
  var onPresentationChange: (Bool) -> Void = { _ in }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: L10n.tr("Share…"), target: context.coordinator, action: #selector(Coordinator.share(_:)))
    // SwiftUI draws the capsule; AppKit keeps the anchor the sharing picker needs.
    button.isBordered = false
    button.attributedTitle = NSAttributedString(
      string: L10n.tr("Share…"),
      attributes: [
        .foregroundColor: NSColor.white,
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      ])
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.items = items
    context.coordinator.onPresentationChange = onPresentationChange
    button.isEnabled = !items.isEmpty
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  @MainActor
  final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var items: [URL] = []
    var picker: NSSharingServicePicker?
    var onPresentationChange: (Bool) -> Void = { _ in }
    @objc func share(_ sender: NSButton) {
      guard !items.isEmpty else { return }
      picker = NSSharingServicePicker(items: items)
      picker?.delegate = self
      onPresentationChange(true)
      picker?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    nonisolated func sharingServicePicker(
      _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
      if service == nil {
        Task { @MainActor in
          self.onPresentationChange(false)
          self.picker = nil
        }
      }
    }
    nonisolated func sharingServicePicker(
      _ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService
    ) -> NSSharingServiceDelegate? { self }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
      onPresentationChange(false)
      picker = nil
    }
    func sharingService(
      _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error
    ) {
      onPresentationChange(false)
      picker = nil
    }
  }
}

