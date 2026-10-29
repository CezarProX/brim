// LiquidPlayerSettingsSection.swift
// Brim
//
// Floating "Liquid Player" settings: pop-out from the notch, level, menu-bar drop-down.

import SwiftUI

struct LiquidPlayerSettingsSection: View {
  @State private var popsOut = AppSettings.shared.notchPlayerDragPopsOut
  @State private var overApps = AppSettings.shared.liquidPlayerFloatsOverApps
  @State private var menuBar = AppSettings.shared.liquidPlayerMenuBarMode
  @State private var showSong = AppSettings.shared.liquidPlayerShowsSongInMenuBar
  @State private var autoHide = AppSettings.shared.liquidPlayerAutoHides
  @State private var size = AppSettings.shared.liquidPlayerSize

  var body: some View {
    Group {
      group("Floating player") {
        Toggle("Dragging the notch player pops it out to floating", isOn: $popsOut)
          .onChange(of: popsOut) { _, value in AppSettings.shared.notchPlayerDragPopsOut = value }
        Toggle("Float over other apps", isOn: $overApps)
          .onChange(of: overApps) { _, value in AppSettings.shared.liquidPlayerFloatsOverApps = value }
        Picker("Size", selection: $size) {
            ForEach(LiquidPlayerSize.allCases) { Text($0.title).tag($0) }
          }
        .pickerStyle(.segmented).fixedSize()
        .onChange(of: size) { _, value in AppSettings.shared.liquidPlayerSize = value }
        note("Drag the cover or title down to pull the player out. Swipe two fingers up or down on it to switch between Mini, Player and Expanded; the close button puts it back in the notch.")
      }
      group("Menu bar") {
        Toggle("Show a menu-bar item that drops the player down", isOn: $menuBar)
          .onChange(of: menuBar) { _, value in AppSettings.shared.liquidPlayerMenuBarMode = value }
        Toggle("Show the song in the menu bar", isOn: $showSong)
          .disabled(!menuBar)
          .onChange(of: showSong) { _, value in AppSettings.shared.liquidPlayerShowsSongInMenuBar = value }
        Toggle("Hide the drop-down 3 seconds after the pointer leaves", isOn: $autoHide)
          .disabled(!menuBar)
          .onChange(of: autoHide) { _, value in AppSettings.shared.liquidPlayerAutoHides = value }
      }
    }
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }
}
