// LockScreenSettingsSection.swift
// Brim
//
// Lock-screen cards: master toggle, which cards to show, sounds and the notch padlock animation.

import SwiftUI

struct LockScreenSettingsSection: View {
    @State private var enabled = AppSettings.shared.lockScreenEnabled
    @State private var media = AppSettings.shared.lockScreenMediaCard
    @State private var timer = AppSettings.shared.lockScreenTimerCard
    @State private var awake = AppSettings.shared.lockScreenAwakeCard
    @State private var status = AppSettings.shared.lockScreenStatusRow
    @State private var animation = AppSettings.shared.lockScreenNotchAnimation
    @State private var screensaver = AppSettings.shared.lockScreenDuringScreensaver
    @State private var look = AppSettings.shared.lockScreenLook
    @State private var hideAfter = AppSettings.shared.lockScreenHideAfterPausedMinutes
    @State private var lockSound = AppSettings.shared.lockScreenLockSound ?? LockScreenSounds.none
    @State private var unlockSound = AppSettings.shared.lockScreenUnlockSound ?? LockScreenSounds.none
    @State private var sounds = [LockScreenSounds.none] + LockScreenSounds.available()
    @State private var availability = LockScreenController.shared.availability

    private var unavailable: Bool { availability == .notAvailableOnThisMac }

    var body: some View {
        Group {
            section("Lock screen") {
                Toggle("Show cards on the lock screen", isOn: $enabled)
                    .disabled(unavailable && !enabled)
                    .onChange(of: enabled) { _, value in
                        AppSettings.shared.lockScreenEnabled = value
                        LockScreenController.shared.settingsChanged()
                        availability = LockScreenController.shared.availability
                    }
                if unavailable {
                    Label("Not available on this macOS", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                Text("Drawing above the lock screen uses a private macOS interface (SkyLight) that Apple can change in any update. If it is missing, the cards switch themselves off; nothing else in Brim is affected. Everything stays on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Group {
                section("Cards") {
                    Toggle("Now Playing with transport controls", isOn: binding($media, \.lockScreenMediaCard))
                    Stepper(value: $hideAfter, in: 0...60) {
                        Text(hideAfter == 0 ? "Hide the song as soon as it pauses"
                             : "Hide a paused song after \(hideAfter) min")
                    }
                    .onChange(of: hideAfter) { _, value in AppSettings.shared.lockScreenHideAfterPausedMinutes = value }
                    .disabled(!media)
                    Toggle("Timer and Pomodoro", isOn: binding($timer, \.lockScreenTimerCard))
                    Toggle("Keep Awake (High Alert)", isOn: binding($awake, \.lockScreenAwakeCard))
                    Toggle("Status row under the clock (battery, next event)", isOn: binding($status, \.lockScreenStatusRow))
                    Toggle("Keep visible during the screen saver", isOn: binding($screensaver, \.lockScreenDuringScreensaver))
                    Picker("Widget look", selection: $look) {
                        ForEach(LockScreenLook.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: look) { _, value in AppSettings.shared.lockScreenLook = value }
                }
                section("Sounds and animation") {
                    soundPicker("Lock sound", selection: $lockSound) { AppSettings.shared.lockScreenLockSound = $0 }
                    soundPicker("Unlock sound", selection: $unlockSound) { AppSettings.shared.lockScreenUnlockSound = $0 }
                    Toggle("Padlock animation in the notch when locking and unlocking",
                           isOn: binding($animation, \.lockScreenNotchAnimation))
                }
            }
            .disabled(!enabled)
        }
    }

    private func binding(_ state: Binding<Bool>, _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.wrappedValue }, set: { value in
            state.wrappedValue = value
            AppSettings.shared[keyPath: keyPath] = value
        })
    }

    private func soundPicker(_ title: String, selection: Binding<String>, store: @escaping (String?) -> Void) -> some View {
        Picker(title, selection: selection) {
            ForEach(sounds, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, name in
            store(name == LockScreenSounds.none ? nil : name)
            LockScreenSounds.play(name)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
      SettingsSection(title) { content() }
    }
}
