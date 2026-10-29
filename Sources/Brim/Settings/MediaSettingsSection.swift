// MediaSettingsSection.swift
// Brim
//
// Media / Lyrics / Apple Music Controls settings for the island.

import SwiftUI

struct MediaSettingsSection: View {
  @State private var lyrics = AppSettings.shared.lyricsEnabled
  @State private var autoExpand = AppSettings.shared.lyricsAutoExpand
  @State private var swipe = AppSettings.shared.trackSwipeEnabled
  @State private var reverse = AppSettings.shared.reverseSwipeDirection
  @State private var live = AppSettings.shared.liveVisualizerEnabled
  @State private var style = AppSettings.shared.visualizerStyle
  @State private var scroll = AppSettings.shared.scrollLongNames
  @State private var keepSong = AppSettings.shared.keepSongNameVisible
  @State private var keepArtist = AppSettings.shared.keepArtistVisible
  @State private var notchTitle = AppSettings.shared.notchTrackTitle
  @State private var hideFullscreen = AppSettings.shared.hideMediaInFullscreen
  @State private var left = AppSettings.shared.mediaLeftButtons
  @State private var right = AppSettings.shared.mediaRightButtons
  @State private var motionArt = AppSettings.shared.mediaMotionArtwork
  @State private var floatingLyrics = AppSettings.shared.mediaFloatingLyrics
  @State private var defaultApp = AppSettings.shared.defaultMusicApp
  @ObservedObject private var nowPlaying = NowPlayingModel.shared

  private static let defaultApps: [(id: String, name: String)] = [
    ("", "Automatic"), ("com.apple.Music", "Apple Music"), ("com.spotify.client", "Spotify"),
  ]

  var body: some View {
    Group {
      SettingsSection(
        "Lyrics",
        footer: "Opt-in and online: the song title, artist, album and length are sent to lrclib.net over HTTPS to find lyrics. Results are cached on this Mac."
      ) {
        Toggle("Show timed lyrics", isOn: $lyrics)
          .onChange(of: lyrics) { _, value in
            AppSettings.shared.lyricsEnabled = value
            MediaServices.shared.sync()
          }
        Toggle("Auto-expand lyrics when a song has them", isOn: $autoExpand)
          .disabled(!lyrics)
          .onChange(of: autoExpand) { _, value in AppSettings.shared.lyricsAutoExpand = value }
        Toggle("Float lyrics over the whole Liquid Player", isOn: $floatingLyrics)
          .disabled(!lyrics)
          .onChange(of: floatingLyrics) { _, value in AppSettings.shared.mediaFloatingLyrics = value }
      }
      SettingsSection("Gestures") {
        Toggle("Swipe two fingers to change track", isOn: $swipe)
          .onChange(of: swipe) { _, value in AppSettings.shared.trackSwipeEnabled = value }
        Toggle("Reverse swipe direction", isOn: $reverse)
          .disabled(!swipe)
          .onChange(of: reverse) { _, value in AppSettings.shared.reverseSwipeDirection = value }
      }
      SettingsSection("Visualizer") {
        Toggle(isOn: $live) {
          Text("Live audio visualizer")
          Text("Reads the playing app's audio levels on this Mac to move the bars; nothing is recorded or leaves the device. macOS asks for audio capture permission the first time. Without it the bars use a built-in animation.")
        }
          .onChange(of: live) { _, value in
            AppSettings.shared.liveVisualizerEnabled = value
            MediaServices.shared.sync()
          }
        Picker("Style", selection: $style) {
          ForEach(VisualizerStyle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).fixedSize()
        .onChange(of: style) { _, value in AppSettings.shared.visualizerStyle = value }
      }
      SettingsSection("Titles") {
        Toggle("Scroll long names", isOn: $scroll)
          .onChange(of: scroll) { _, value in AppSettings.shared.scrollLongNames = value }
        Toggle("Show the track title in the notch", isOn: $notchTitle)
          .onChange(of: notchTitle) { _, value in AppSettings.shared.notchTrackTitle = value }
        Toggle("Keep song name visible (Macs without a notch)", isOn: $keepSong)
          .onChange(of: keepSong) { _, value in AppSettings.shared.keepSongNameVisible = value }
        Toggle("Keep artist visible (Macs without a notch)", isOn: $keepArtist)
          .onChange(of: keepArtist) { _, value in AppSettings.shared.keepArtistVisible = value }
        Toggle("Hide media while an app is fullscreen", isOn: $hideFullscreen)
          .onChange(of: hideFullscreen) { _, value in AppSettings.shared.hideMediaInFullscreen = value }
      }
      SettingsSection(
        "Artwork",
        footer: "Apple Music's animated covers and Spotify Canvas have no public source, so Brim slowly zooms and pans the still cover instead. Off when Reduce Motion is on."
      ) {
        Toggle("Gentle cover motion while playing", isOn: $motionArt)
          .onChange(of: motionArt) { _, value in AppSettings.shared.mediaMotionArtwork = value }
      }
      SettingsSection(
        "Player buttons",
        footer: "Repeat works in Apple Music (off, all, one) and Spotify (off, all). Favorite and Add to Playlist are Apple Music only: Spotify has no like command in its scripting interface, so a Favorite slot shows Shuffle there. Buttons a player cannot honour stay hidden."
      ) {
        buttonPickers("Left", selection: $left) { AppSettings.shared.mediaLeftButtons = $0 }
        buttonPickers("Right", selection: $right) { AppSettings.shared.mediaRightButtons = $0 }
      }
      SettingsSection("Sources", footer: "Each source asks macOS for permission the first time you turn it on.") {
        Picker("Default music app", selection: $defaultApp) {
          ForEach(Self.defaultApps, id: \.id) { Text($0.name).tag($0.id) }
        }
        .onChange(of: defaultApp) { _, value in AppSettings.shared.defaultMusicApp = value }
        ForEach(NowPlayingSource.allCases) { source in
          Toggle(source.name, isOn: sourceBinding(source))
        }
      }
    }
  }

  private func sourceBinding(_ source: NowPlayingSource) -> Binding<Bool> {
    Binding(
      get: { nowPlaying.enabledSources.contains(source) },
      set: { $0 ? nowPlaying.connect(source) : nowPlaying.disconnect(source) })
  }

  private func buttonPickers(_ title: String, selection: Binding<[MediaButtonKind]>,
                             save: @escaping ([MediaButtonKind]) -> Void) -> some View {
    LabeledContent(LocalizedStringKey(title)) {
      HStack(spacing: 8) {
      ForEach(0..<2, id: \.self) { slot in
        Picker("", selection: Binding(
          get: { slot < selection.wrappedValue.count ? selection.wrappedValue[slot] : .none },
          set: { kind in
            var next = selection.wrappedValue
            while next.count <= slot { next.append(.none) }
            next[slot] = kind
            let cleaned = next.filter { $0 != .none }
            selection.wrappedValue = cleaned
            save(cleaned)
          })) {
          ForEach(MediaButtonKind.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden().fixedSize()
      }
      }
    }
  }
}
