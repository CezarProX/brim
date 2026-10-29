// CaptureActions.swift
// Brim
//
// Terminal actions that can be performed on a finished capture image.
// `CaptureCoordinator.finishWithImage(_:)` dispatches into these based on
// `AppSettings`.

import AppKit

@MainActor
enum CaptureActions {

    // MARK: - Copy

    /// Copies `image` to the general pasteboard as PNG + TIFF, flattening
    /// onto white first if the user has disabled transparency preservation.
    /// Never writes a file to disk.
    static func copyToClipboard(_ image: NSImage) {
        do {
            let preserveTransparency = AppSettings.shared.preserveTransparency
            var sourceImage = preserveTransparency ? image : try ImageEncoder.flattenOntoWhite(image)

            if !AppSettings.shared.copyAtOriginalResolution {
                sourceImage = try downscaledToPointSize(sourceImage, preserveTransparency: preserveTransparency)
            }

            guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ImageEncoder.EncodingError.noBitmapSource
            }

            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw ImageEncoder.EncodingError.representationFailed
            }
            let tiffData = sourceImage.tiffRepresentation

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("io.github.cezarprox.brim.screenshot"))
            if let tiffData {
                pasteboard.setData(tiffData, forType: .tiff)
            }

            if AppSettings.shared.playSound {
                NSSound(named: "Pop")?.play()
            }

            NotificationCenterHelper.notify(
                title: "Screenshot Copied",
                body: "Screenshot copied to clipboard."
            )
            HistoryStore.shared.recordClipboardCapture(size: ImageEncoder.pixelSizeString(of: image))
        } catch {
            presentErrorAlert(title: "Couldn't Copy Screenshot", message: error.localizedDescription)
        }
    }

    /// Downscales `image` so its pixel dimensions match its point size
    /// (i.e. rendered at 1x instead of full retina resolution). Used when
    /// `copyAtOriginalResolution` is disabled. Alpha is preserved or
    /// discarded per `preserveTransparency`, matching the (possibly already
    /// flattened) `image` passed in.
    private static func downscaledToPointSize(_ image: NSImage, preserveTransparency: Bool) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageEncoder.EncodingError.noBitmapSource
        }

        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        let bitmapInfo: CGImageAlphaInfo = preserveTransparency ? .premultipliedLast : .noneSkipLast

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ImageEncoder.EncodingError.representationFailed
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let downscaled = context.makeImage() else {
            throw ImageEncoder.EncodingError.representationFailed
        }

        return NSImage(cgImage: downscaled, size: image.size)
    }

    // MARK: - Save

    /// Saves `image` to disk. If auto-save is configured (`autoSave` +
    /// `defaultSaveFolder`), writes directly there; otherwise presents an
    /// `NSSavePanel`. Runs standalone (not sheet-attached) since the calling
    /// overlay/editor window may be in the process of closing.
    ///
    /// - Parameter onCompletion: invoked on the main thread once the save
    ///   flow finishes — after the auto-save write attempt, or after the
    ///   save panel is dismissed (either OK or Cancel). Lets callers that
    ///   keep the capture session alive (`closeAfterSave == false`) know
    ///   when it's safe to restore the overlay.
    /// - Parameter onSuccess: invoked only after a file was written successfully.
    /// - Parameter forceSavePanel: bypasses auto-save for an explicit Save As action.
    static func save(
        _ image: NSImage,
        from window: NSWindow?,
        onCompletion: (() -> Void)? = nil,
        onSuccess: (() -> Void)? = nil,
        forceSavePanel: Bool = false
    ) {
        if !forceSavePanel, AppSettings.shared.autoSave, let folder = AppSettings.shared.defaultSaveFolder {
            autoSave(image, to: folder, onCompletion: onCompletion, onSuccess: onSuccess)
        } else {
            presentSavePanel(for: image, from: window, onCompletion: onCompletion, onSuccess: onSuccess)
        }
    }

    private static func autoSave(_ image: NSImage, to folder: URL, onCompletion: (() -> Void)?, onSuccess: (() -> Void)?) {
        defer { onCompletion?() }

        let format = currentDefaultFormat()
        let baseName = AppSettings.defaultFileName()
        let destination = uniqueURL(in: folder, baseName: baseName, ext: format.fileExtension)

        // Defense-in-depth: even though `baseName` is sanitized upstream,
        // verify the resolved destination actually stays inside the chosen
        // folder before writing anything to disk.
        let folderPath = folder.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/") else {
            presentErrorAlert(
                title: "Couldn't Save Screenshot",
                message: "The resolved file location is outside the selected save folder."
            )
            return
        }

        do {
            let data = try ImageEncoder.data(
                from: image,
                format: format,
                preserveTransparency: AppSettings.shared.preserveTransparency,
                jpgQuality: AppSettings.shared.jpgQuality
            )
            try data.write(to: destination, options: .atomic)
            onSuccess?()

            NotificationCenterHelper.notify(
                title: "Screenshot Saved",
                body: destination.lastPathComponent
            )
            HistoryStore.shared.add(
                HistoryEntry(kind: .save, fileURL: destination, pixelSize: ImageEncoder.pixelSizeString(of: image))
            )
        } catch {
            presentErrorAlert(title: "Couldn't Save Screenshot", message: error.localizedDescription)
        }
    }

    private static func presentSavePanel(for image: NSImage, from window: NSWindow?, onCompletion: (() -> Void)?, onSuccess: (() -> Void)?) {
        let format = currentDefaultFormat()
        let baseName = AppSettings.defaultFileName()

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"

        let directory = AppSettings.shared.rememberLastSaveLocation
            ? (AppSettings.shared.lastSaveLocation ?? AppSettings.shared.defaultSaveFolder)
            : AppSettings.shared.defaultSaveFolder
        if let directory {
            panel.directoryURL = directory
        }

        let accessory = SaveFormatAccessory(panel: panel, baseName: baseName, initialFormat: format)
        panel.accessoryView = accessory.view

        // Standalone `begin` (no sheet parent window) — the overlay/editor
        // window that triggered this may already be tearing itself down.
        panel.begin { response in
            Task { @MainActor in
                handleSavePanelResponse(response, panel: panel, image: image, accessory: accessory, onSuccess: onSuccess)
                onCompletion?()
            }
        }
    }

    private static func handleSavePanelResponse(
        _ response: NSApplication.ModalResponse,
        panel: NSSavePanel,
        image: NSImage,
        accessory: SaveFormatAccessory,
        onSuccess: (() -> Void)?
    ) {
        guard response == .OK, let destination = panel.url else { return }

        do {
            let data = try ImageEncoder.data(
                from: image,
                format: accessory.selectedFormat,
                preserveTransparency: AppSettings.shared.preserveTransparency,
                jpgQuality: AppSettings.shared.jpgQuality
            )
            try data.write(to: destination, options: .atomic)
            onSuccess?()

            if AppSettings.shared.rememberLastSaveLocation {
                AppSettings.shared.lastSaveLocation = destination.deletingLastPathComponent()
            }

            NotificationCenterHelper.notify(
                title: "Screenshot Saved",
                body: "Screenshot saved successfully."
            )
            HistoryStore.shared.add(
                HistoryEntry(kind: .save, fileURL: destination, pixelSize: ImageEncoder.pixelSizeString(of: image))
            )
        } catch {
            presentErrorAlert(title: "Couldn't Save Screenshot", message: error.localizedDescription)
        }
    }

    private static func currentDefaultFormat() -> ImageEncoder.Format {
        AppSettings.shared.defaultImageFormat == "jpg" ? .jpg : .png
    }

    /// Returns a URL in `directory` for `baseName.ext`, appending " 2",
    /// " 3", etc. until a non-colliding name is found.
    private static func uniqueURL(in directory: URL, baseName: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    // MARK: - Print

    /// Sends `image` to the system print flow via an `NSImageView` sized to
    /// the image, scaled to fit the page.
    static func print(_ image: NSImage) {
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let operation = NSPrintOperation(view: imageView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    // MARK: - Upload

    /// Uploads `image` as PNG to `AppSettings.uploadServiceURL`. On success,
    /// optionally copies the link to the clipboard and records the upload in
    /// history. On failure, offers a single retry.
    @discardableResult
    static func upload(_ image: NSImage) async -> URL? {
        guard confirmUploadHost() else { return nil }
        return await performUpload(image, retriesRemaining: 1)
    }

    /// The first upload to a host names it and says the link is public; nothing is sent until the
    /// user agrees. Asked again only when the upload service changes.
    private static func confirmUploadHost() -> Bool {
        let settings = AppSettings.shared
        guard let host = UploadConsent.hostNeedingConsent(
            serviceURL: settings.uploadServiceURL, acknowledged: settings.uploadHostAcknowledged)
        else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Upload to %@?", host)
        alert.informativeText = L10n.tr(
            "The screenshot is sent to this file host and gets a public link. Anyone with the link can open it, and Brim cannot delete it. You can change the service in Settings > Upload.")
        alert.addButton(withTitle: L10n.tr("Upload"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        // Above the capture overlay, which can still be open during an automatic upload.
        alert.window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        settings.uploadHostAcknowledged = host
        return true
    }

    private static func performUpload(_ image: NSImage, retriesRemaining: Int) async -> URL? {
        do {
            let pngData = try ImageEncoder.pngDataPreservingAlpha(from: image)
            let url = try await Uploader.upload(pngData: pngData, to: AppSettings.shared.uploadServiceURL)

            if AppSettings.shared.autoCopyLink {
                copyLinkToClipboard(url)
                NotificationCenterHelper.notify(
                    title: "Screenshot Uploaded",
                    body: "Screenshot uploaded. Link copied to clipboard.\n\(url.absoluteString)"
                )
            } else {
                NotificationCenterHelper.notify(
                    title: "Screenshot Uploaded",
                    body: url.absoluteString
                )
            }

            HistoryStore.shared.add(
                HistoryEntry(kind: .upload, link: url, pixelSize: ImageEncoder.pixelSizeString(of: image))
            )
            return url
        } catch {
            NotificationCenterHelper.notify(title: "Upload Failed", body: error.localizedDescription)

            guard retriesRemaining > 0, presentUploadFailureAlert() else { return nil }
            return await performUpload(image, retriesRemaining: retriesRemaining - 1)
        }
    }

    private static func copyLinkToClipboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    private static func presentUploadFailureAlert() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Upload Failed")
        alert.informativeText = L10n.tr("The screenshot couldn't be uploaded. Would you like to try again?")
        alert.addButton(withTitle: L10n.tr("Retry"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Share

    private static var activeSharingPicker: NSSharingServicePicker?
    private static var activeSharingPickerDelegate: SharingPickerDelegate?

    /// Shows the system share sheet for `image`, anchored to `view`. Falls
    /// back to a clipboard copy if no anchor view is available (the sharing
    /// picker requires a view to present relative to).
    static func share(_ image: NSImage, from view: NSView?) {
        // Without a view to anchor to (the capture overlay, which sits above every popover), the
        // sheet opens from a small invisible window under the pointer.
        let anchorWindow = view == nil ? makeShareAnchorWindow() : nil
        guard let view = view ?? anchorWindow?.contentView else {
            copyToClipboard(image)
            return
        }

        let picker = NSSharingServicePicker(items: [image])
        let delegate = SharingPickerDelegate {
            activeSharingPicker = nil
            activeSharingPickerDelegate = nil
            anchorWindow?.orderOut(nil)
        }
        picker.delegate = delegate
        activeSharingPicker = picker
        activeSharingPickerDelegate = delegate
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private static func makeShareAnchorWindow() -> NSWindow? {
        let pointer = NSEvent.mouseLocation
        let window = NSWindow(contentRect: CGRect(x: pointer.x - 1, y: pointer.y - 1, width: 2, height: 2),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }

    /// Releases the static `activeSharingPicker` reference once the user
    /// finishes with the share sheet (choosing a service or dismissing it),
    /// preventing it from being retained indefinitely.
    private final class SharingPickerDelegate: NSObject, NSSharingServicePickerDelegate {
        private let onFinished: () -> Void

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            // Deferred to the next run loop turn: per Apple's docs, the
            // picker/delegate must not be released synchronously from
            // within this callback.
            DispatchQueue.main.async { [onFinished] in
                onFinished()
            }
        }
    }

    // MARK: - Error presentation

    private static func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("OK"))
        alert.runModal()
    }
}
