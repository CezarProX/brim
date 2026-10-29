// RecordingBar.swift
// Brim
//
// The floating recorder bar shown before a recording: pick Display / Window / Area, toggle the
// microphone and system audio, choose frame rate, Retina and countdown, then Record.

import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI

struct RecordableWindow: Identifiable, Equatable {
    let id: CGWindowID
    let app: String
    let title: String
}

@MainActor
final class RecordingBarModel: ObservableObject {
    @Published var kind: RecordingSourceKind
    @Published var windows: [RecordableWindow] = []
    @Published var windowID: CGWindowID?
    @Published var microphone: Bool { didSet { settings.recordingMicrophone = microphone } }
    @Published var systemAudio: Bool { didSet { settings.recordingSystemAudio = systemAudio } }
    @Published var fps: Int { didSet { settings.recordingFPS = fps } }
    @Published var retina: Bool { didSet { settings.recordingRetina = retina } }
    @Published var countdown: Int { didSet { settings.recordingCountdown = countdown } }

    private let settings: AppSettings
    var onRecord: () -> Void = {}
    var onClose: () -> Void = {}

    init(settings: AppSettings = .shared) {
        self.settings = settings
        kind = RecordingSourceKind(rawValue: settings.recordingSourceKind) ?? .display
        microphone = settings.recordingMicrophone
        systemAudio = settings.recordingSystemAudio
        fps = settings.recordingFPS
        retina = settings.recordingRetina
        countdown = settings.recordingCountdown
    }

    func select(_ kind: RecordingSourceKind) {
        self.kind = kind
        settings.recordingSourceKind = kind.rawValue
        if kind == .window, windows.isEmpty { Task { await loadWindows() } }
    }

    func loadWindows() async {
        guard let found = try? await RecordingSourceResolver.pickableWindows() else { return }
        windows = found.map { RecordableWindow(id: $0.windowID, app: $0.owningApplication?.applicationName ?? "",
                                               title: $0.title ?? "") }
        if windowID == nil || !windows.contains(where: { $0.id == windowID }) { windowID = windows.first?.id }
    }

    var canRecord: Bool { kind != .window || windowID != nil }
}

struct RecordingBarView: View {
    @ObservedObject var model: RecordingBarModel

    var body: some View {
        HStack(spacing: 6) {
            iconButton("xmark", help: "Close the recorder (Esc)", action: model.onClose)
            divider
            ForEach(RecordingSourceKind.allCases, id: \.self) { kind in sourceButton(kind) }
            if model.kind == .window { windowMenu }
            divider
            toggle(model.microphone ? "mic.fill" : "mic.slash", on: model.microphone,
                   help: model.microphone ? "Microphone on" : "Microphone off") { model.microphone.toggle() }
            toggle(model.systemAudio ? "speaker.wave.2.fill" : "speaker.slash", on: model.systemAudio,
                   help: model.systemAudio ? "System audio on" : "System audio off") { model.systemAudio.toggle() }
            optionsMenu
            Button(action: model.onRecord) {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                    Text("Record").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Color(red: 1, green: 0.27, blue: 0.23)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!model.canRecord)
            .opacity(model.canRecord ? 1 : 0.5)
            .keyboardShortcut(.defaultAction)
            .help("Start a screen recording")
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.11).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 2)
    }

    private func sourceButton(_ kind: RecordingSourceKind) -> some View {
        let selected = model.kind == kind
        return Button { model.select(kind) } label: {
            VStack(spacing: 2) {
                Image(systemName: kind.symbol).font(.system(size: 14, weight: .medium))
                Text(LocalizedStringKey(kind.title)).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 58, height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? .white.opacity(0.16) : .clear))
            .foregroundStyle(selected ? .white : .white.opacity(0.65))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var windowMenu: some View {
        Menu {
            ForEach(model.windows) { window in
                Button(window.title.isEmpty ? window.app : "\(window.app) — \(window.title)") { model.windowID = window.id }
            }
            if model.windows.isEmpty { Text("No windows to record") }
        } label: {
            Text(model.windows.first { $0.id == model.windowID }.map { $0.title.isEmpty ? $0.app : $0.title } ?? L10n.tr("Pick an app window to record"))
                .lineLimit(1).frame(maxWidth: 170)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .task { await model.loadWindows() }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Frame rate", selection: $model.fps) {
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            }
            Toggle("Retina resolution", isOn: $model.retina)
            Picker("Countdown", selection: $model.countdown) {
                Text("No countdown").tag(0)
                Text("3 seconds").tag(3)
                Text("5 seconds").tag(5)
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 32)
        .help("More recording options")
    }

    private func toggle(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? .white.opacity(0.16) : .clear))
                .foregroundStyle(on ? .white : .white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(LocalizedStringKey(help))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help(LocalizedStringKey(help))
    }
}

/// Hosts the bar near the bottom of the display under the pointer.
@MainActor
final class RecordingBarPanel {
    private var panel: NSPanel?
    private var resize: AnyCancellable?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(model: RecordingBarModel) {
        close()
        let host = NSHostingView(rootView: RecordingBarView(model: model))
        let size = host.fittingSize
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let panel = KeyablePanel(contentRect: CGRect(x: visible.midX - 320, y: visible.minY + 90, width: 640, height: size.height),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.setContentSize(size)
        panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 90))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        // The window picker changes the bar's width; keep it centred.
        resize = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak host] _ in
            DispatchQueue.main.async {
                guard let panel = self?.panel, let host else { return }
                let fitted = host.fittingSize
                let centre = panel.frame.midX
                panel.setFrame(CGRect(x: centre - fitted.width / 2, y: panel.frame.minY, width: fitted.width, height: fitted.height),
                               display: true, animate: false)
            }
        }
    }

    func close() {
        resize = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
