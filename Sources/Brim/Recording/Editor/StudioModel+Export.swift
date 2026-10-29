// StudioModel+Export.swift
// Brim
//
// Export to the user's save folder (Settings > Saving, else the Desktop), with progress, cancel and
// Reveal / Copy / Share afterwards.

import AppKit
import Foundation

extension StudioModel {
    var isExporting: Bool {
        if case .running = exportState { return true }
        return false
    }

    /// The configured save folder, or the Desktop.
    var exportFolder: URL {
        settings.defaultSaveFolder
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var candidate = folder.appendingPathComponent(safe).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(safe) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    func export() {
        guard !isExporting else { return }
        if isPlaying { pause() }
        saveNow()
        let settings = exportSettings
        let url = Self.uniqueURL(in: exportFolder, name: title, ext: settings.format.fileExtension)
        let exporter = StudioExporter()
        self.exporter = exporter
        exportState = .running(format: settings.format, progress: 0)
        let inputs = StudioRenderInputs(edit: edit, metadata: metadata, track: track)
        let asset = asset
        Task { [weak self] in
            do {
                try await exporter.export(asset: asset, inputs: inputs, settings: settings, to: url) { value in
                    Task { @MainActor in
                        guard let self, case .running(let format, let old) = self.exportState, value - old >= 0.01 || value >= 1 else { return }
                        self.exportState = .running(format: format, progress: value)
                    }
                }
                self?.finishExport(url)
            } catch StudioExportError.cancelled {
                self?.exportState = .idle
            } catch {
                self?.exportState = .failed(error.localizedDescription)
            }
            self?.exporter = nil
        }
    }

    private func finishExport(_ url: URL) {
        exportState = .finished(url)
        IslandFlashCenter.shared.show(L10n.tr("Recording exported"), symbol: "film.stack", tint: .green, duration: 5,
                                      kind: .general, detail: url.lastPathComponent,
                                      action: HUDAction(title: L10n.tr("Show in Finder"), symbol: "magnifyingglass") {
                                          NSWorkspace.shared.activateFileViewerSelecting([url])
                                      })
    }

    func cancelExport() {
        exporter?.cancel()
    }

    func dismissExportResult() { exportState = .idle }

    func revealExport() {
        guard case .finished(let url) = exportState else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyExport() {
        guard case .finished(let url) = exportState else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        IslandFlashCenter.shared.show(L10n.tr("Copied"), symbol: "doc.on.doc.fill", tint: .blue)
    }

    func shareExport(from view: NSView?) {
        guard case .finished(let url) = exportState, let view else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
