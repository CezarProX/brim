import SwiftUI

/// The 64-point slot style used beside the transport row of the notch player.
private struct SlotLabel: View {
  let symbol: String
  var tint: Color = .white.opacity(0.55)
  var hovered = false

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 28, weight: .semibold))
      .foregroundStyle(tint)
      .contentTransition(.symbolEffect(.replace))
      .frame(width: 64, height: 64)
      .background(hovered ? IslandFill.subtle : .clear, in: Circle())
      .contentShape(Circle())
  }
}

/// Repeat in a notch-player slot: tap cycles off, all, one (Apple Music) or off, all (Spotify).
struct MusicRepeatSlotButton: View {
  let mode: RepeatMode
  let disabled: Bool
  let action: () -> Void
  @State private var hovered = false
  @State private var taps = 0

  var body: some View {
    Button {
      taps += 1
      action()
    } label: {
      SlotLabel(symbol: mode.symbol, tint: mode.isActive ? .white : .white.opacity(0.55), hovered: hovered)
        .symbolEffect(.bounce, value: taps)
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.86))
    .disabled(disabled)
    .onHover { hovered = $0 }
    .help(mode.title)
    .accessibilityLabel("Repeat")
    .accessibilityValue(mode.title)
  }
}

/// Add the current Apple Music track to a user playlist, chosen from a menu.
struct MusicPlaylistSlotButton: View {
  let disabled: Bool
  @ObservedObject var playlists: MusicPlaylistsModel = .shared

  var body: some View {
    MusicPlaylistMenu(playlists: playlists) {
      // A menu label must be one plain Image: wrapping it in a view makes macOS draw it at body size.
      Image(systemName: PlaylistFeedback.symbol(for: playlists.outcome))
        .resizable().scaledToFit().fontWeight(.semibold)
        .foregroundStyle(PlaylistFeedback.tint(for: playlists.outcome))
        .frame(width: 32, height: 32)
        .frame(width: 64, height: 64)
    }
    .disabled(disabled)
  }
}

/// Symbol and colour for the add-to-playlist button, so success and failure show where the user looked.
enum PlaylistFeedback {
  static func symbol(for outcome: MusicPlaylistsModel.Outcome) -> String {
    switch outcome {
    case .none: return "text.badge.plus"
    case .added: return "checkmark.circle.fill"
    case .failed: return "exclamationmark.triangle.fill"
    }
  }

  static func tint(for outcome: MusicPlaylistsModel.Outcome) -> Color {
    switch outcome {
    case .none: return .white.opacity(0.55)
    case .added: return .green
    case .failed: return .orange
    }
  }

  static func help(for outcome: MusicPlaylistsModel.Outcome) -> String {
    switch outcome {
    case .none: return "Add to Playlist"
    case .added(let name): return "Added to \(name)"
    case .failed(let message): return message
    }
  }
}

/// The playlist menu itself; the label is supplied by the caller so every player styles it natively.
struct MusicPlaylistMenu<Label: View>: View {
  @ObservedObject var playlists: MusicPlaylistsModel
  @ViewBuilder var label: () -> Label

  var body: some View {
    Menu {
      if playlists.playlists.isEmpty {
        Text(playlists.isLoading ? "Loading playlists…" : "No playlists found")
      }
      ForEach(playlists.playlists, id: \.self) { name in
        Button(name) { playlists.add(to: name) }
      }
    } label: {
      label()
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .onAppear { playlists.refresh() }
    .help(PlaylistFeedback.help(for: playlists.outcome))
    .accessibilityLabel("Add to Playlist")
    .accessibilityValue(PlaylistFeedback.help(for: playlists.outcome))
  }
}
