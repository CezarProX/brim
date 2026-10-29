// CaptureCoordinator.swift
// Brim
//
// The central state machine for a capture session. This is the shared
// contract other modules hang off of: HotkeyManager and the status-bar menu
// both call `startCapture()`; `OverlayController` reports back through its
// `onAction` / `onCancelled` callbacks, wired up once here.
//
// End-to-end flow:
//   1. Global hotkey (or menu item) fires -> `startCapture()`.
//   2. Freeze the current frame of every connected display
//      (`ScreenCapturer.captureFullScreens()`).
//   3. `OverlayController.shared.begin(screens:frozenImages:)` shows one
//      borderless overlay window per screen displaying its frozen image, and
//      lets the user drag out a selection, annotate it, and pick a final
//      action from the floating action bar (or a keyboard shortcut).
//   4. `OverlayController.onAction` fires with the chosen `OverlayAction` and
//      the fully composited (cropped + annotated) image; this coordinator
//      dispatches to `CaptureActions` per `AppSettings` and tears the overlay
//      down.
//   5. Cancelling at any point (Esc, the action bar's close button) fires
//      `onCancelled`, which also tears the overlay down.

import AppKit

@MainActor
final class CaptureCoordinator {

    static let shared = CaptureCoordinator()

    /// Where the current capture session is in its lifecycle.
    enum CaptureState {
        /// No capture session in progress.
        case idle
        /// Overlay windows are showing frozen screen images and the user is
        /// selecting/annotating a region.
        case selecting
    }

    private(set) var state: CaptureState = .idle
    private var shelfCaptureID = UUID()

    private init() {
        OverlayController.shared.onAction = { [weak self] action, image in
            self?.handleOverlayAction(action, image: image)
        }
        OverlayController.shared.onCancelled = { [weak self] in
            self?.handleCancelled()
        }
    }

    /// Begins a new capture session. No-op if a session is already in
    /// progress (call `cancelCapture()` first if you need to restart).
    func startCapture() {
        guard state == .idle else { return }

        state = .selecting
        shelfCaptureID = UUID()
        NotchShelfController.shared.suspend()
        CaptureThumbnailCenter.shared.captureWillBegin()

        Task {
            do {
                let frozen = try await ScreenCapturer.captureFullScreens()
                // The capture may have been cancelled (e.g. `cancelCapture()`
                // or the user pressing Esc before the frozen images finished
                // loading) while we were awaiting; discard the result rather
                // than reviving a dead session.
                guard state == .selecting else { return }
                OverlayController.shared.begin(screens: NSScreen.screens, frozenImages: frozen)
            } catch {
                state = .idle
                NotchShelfController.shared.resume()
                if case ScreenCapturer.CaptureError.permissionDenied = error {
                    PermissionsHelper.showScreenRecordingRecovery()
                } else {
                    NotificationCenterHelper.notify(title: "Capture Failed", body: error.localizedDescription)
                }
            }
        }
    }

    /// Cancels any in-progress capture session and tears down the overlay,
    /// returning to `.idle`.
    func cancelCapture() {
        guard state != .idle else { return }
        OverlayController.shared.dismiss()
        state = .idle
        NotchShelfController.shared.resume()
    }

    /// For callers that hand over a finished image (Command Center's screen and window captures).
    /// They have no overlay to press Copy in, so the default is `.copy`: copied, on the shelf and
    /// shown as a thumbnail, like the system's own screenshots.
    func finishWithImage(_ image: NSImage, action: OverlayAction = .copy) {
        // Each finished image is its own capture, so a second one never replaces the first card.
        shelfCaptureID = UUID()
        handleOverlayAction(action, image: image)
    }

    // MARK: - Overlay callbacks

    /// Dispatches a finished (cropped + annotated) capture to the
    /// appropriate `CaptureActions`, per `AppSettings`, and tears down the
    /// overlay when the action represents a completed session.
    private func handleOverlayAction(_ action: OverlayAction, image: NSImage) {
        CaptureThumbnailCenter.shared.captureFinished(
            image, action: action, captureID: shelfCaptureID, screen: OverlayController.shared.activeScreen)
        if AppSettings.shared.notchShelfEnabled {
            let shouldRecord: Bool
            if case .confirm = action { shouldRecord = AppSettings.shared.copyAfterSelection }
            else { shouldRecord = true }
            if shouldRecord {
                ShelfStore.shared.add(image, id: shelfCaptureID)
            }
        }
        switch action {
        case .copy:
            // Explicit Cmd+C (or the action bar's copy button) always copies.
            performCopyAction(image)

        case .confirm:
            // Enter copies only when the setting is enabled (spec: "Enter
            // copies only when the setting is enabled"). Otherwise Enter
            // just confirms the selection — the overlay stays open and the
            // user must press Cmd+C explicitly to copy.
            if AppSettings.shared.copyAfterSelection {
                performCopyAction(image)
            }

        case .save:
            if AppSettings.shared.closeAfterSave {
                // Dismiss first so the save panel isn't obscured by the
                // screensaver-level overlay window.
                endSession()
                CaptureActions.save(image, from: nil)
            } else {
                // Keep the capture session alive: hide the overlay windows
                // (without destroying selection/editing state) while the
                // save panel is up, then restore them once saving finishes.
                OverlayController.shared.setHidden(true)
                CaptureActions.save(image, from: nil, onCompletion: {
                    OverlayController.shared.setHidden(false)
                })
            }

        case .upload:
            Task { await CaptureActions.upload(image) }
            endSession()

        case .print:
            // Dismiss first so the print panel isn't obscured by the
            // screensaver-level overlay window.
            endSession()
            CaptureActions.print(image)

        case .share:
            // The overlay sits above every popover, so it goes first; the share sheet then opens
            // under the pointer.
            endSession()
            CaptureActions.share(image, from: nil)
        }
    }

    /// Copies `image` to the clipboard and, per `AppSettings`, optionally
    /// also fires a background upload and/or closes the overlay session.
    ///
    /// `autoUpload`: when enabled, ALSO fires a fire-and-forget upload
    /// alongside the copy (`CaptureActions.upload` already handles
    /// `autoCopyLink` + notifications + history, so nothing further is
    /// needed here). Shared by both `.copy` and a `.confirm` that resolves
    /// to a copy (`copyAfterSelection == true`).
    private func performCopyAction(_ image: NSImage) {
        CaptureActions.copyToClipboard(image)

        if AppSettings.shared.autoUpload {
            Task { await CaptureActions.upload(image) }
        }

        // A finished image handed over without an overlay has no session to end.
        if AppSettings.shared.closeAfterCopy, state != .idle {
            endSession()
        }
    }

    private func handleCancelled() {
        OverlayController.shared.dismiss()
        state = .idle
        NotchShelfController.shared.resume()
    }

    /// Tears down the overlay and returns to `.idle`. Shared by every
    /// overlay action that represents a completed capture session.
    private func endSession() {
        OverlayController.shared.dismiss()
        state = .idle
        NotchShelfController.shared.resume()
    }
}
