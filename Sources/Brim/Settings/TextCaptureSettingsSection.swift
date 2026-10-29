// TextCaptureSettingsSection.swift
// Brim

import SwiftUI

struct TextCaptureSettingsSection: View {
  @State private var enabled = AppSettings.shared.textCaptureEnabled
  @State private var shortcut = AppSettings.shared.textCaptureShortcut
  @State private var language = AppSettings.shared.textCaptureLanguage
  @State private var correction = AppSettings.shared.textCaptureLanguageCorrection
  @State private var completion = AppSettings.shared.textCaptureCompletion
  @State private var autoCopy = AppSettings.shared.textCaptureAutoCopyCodes
  @State private var keepHistory = AppSettings.shared.textCaptureKeepHistory
  @State private var languages: [(code: String, name: String)] = []

  var body: some View {
    SettingsSection("Text Capture") {
      Toggle("Enable the Text Capture droplet", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.textCaptureEnabled = value
          TextCaptureController.shared.settingsChanged()
        }
      Text("Select any part of the screen, or choose an image or PDF, and Brim reads the text and any QR code or barcode on this Mac. Nothing is uploaded.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        DropletShortcutField(title: "Capture shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.textCaptureShortcut = value
            TextCaptureController.shared.settingsChanged()
          }
        Picker("When text is found", selection: $completion) {
          ForEach(TextCaptureCompletion.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: completion) { _, value in AppSettings.shared.textCaptureCompletion = value }
        Picker("Language", selection: $language) {
          Text("Detect automatically").tag("auto")
          ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
        }
        .onChange(of: language) { _, value in AppSettings.shared.textCaptureLanguage = value }
        Toggle("Correct words using the language", isOn: $correction)
          .onChange(of: correction) { _, value in AppSettings.shared.textCaptureLanguageCorrection = value }
        Toggle("Copy QR code and barcode contents automatically", isOn: $autoCopy)
          .onChange(of: autoCopy) { _, value in AppSettings.shared.textCaptureAutoCopyCodes = value }
        Toggle("Keep the last 100 captures", isOn: $keepHistory)
          .onChange(of: keepHistory) { _, value in AppSettings.shared.textCaptureKeepHistory = value }
        Text("Links from QR codes open only when you click Open. Only web, email, phone and message links can be opened.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .task { languages = TextRecognition.supportedLanguages() }
  }
}
