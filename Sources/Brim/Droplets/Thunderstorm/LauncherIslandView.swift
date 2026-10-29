import AppKit
import SwiftUI

/// The launcher inside the island: one search box for apps, files, clipboard, math and unit
/// conversions. The global shortcut opens the same thing as a floating panel.
@MainActor
struct LauncherIslandView: View {
  @ObservedObject private var state = LauncherEnabledState.shared

  var body: some View {
    Group {
      if state.enabled {
        LauncherSearch()
      } else {
      IslandIntroCard(
        symbol: "bolt.fill", tint: Color(red: 0.55, green: 0.45, blue: 1),
        headline: L10n.tr("One search box for everything on your Mac"),
        lines: [
          ("app.fill", L10n.tr("Open apps and files by typing a few letters")),
          ("equal.circle.fill", L10n.tr("Do math and convert units: 12 * 8, 5 km in mi")),
          ("doc.on.clipboard", L10n.tr("Find things you copied earlier")),
        ],
        actionTitle: L10n.tr("Turn on Launcher"), action: { state.enable() },
        footnote: L10n.tr("Opens anywhere with %@. Everything stays on this Mac.", state.shortcutText))
      }
    }
    .onAppear { state.refresh() }
  }
}

@MainActor
private struct LauncherSearch: View {
  @StateObject private var model = ThunderstormModel()
  @State private var target: NSRunningApplication?
  @FocusState private var focused: Bool
  @ObservedObject private var state = LauncherEnabledState.shared

  private static let examples = ["12 * 8", "5 km in mi", "gh swift", "safari"]

  var body: some View {
    VStack(spacing: 8) {
      IslandSearchField(
        prompt: L10n.tr("Search apps, files, clipboard, math…"), text: $model.query, font: .system(size: 16), height: 38, focus: $focused)
      results.frame(maxWidth: .infinity, maxHeight: .infinity)
      footer.frame(height: 22)
    }
    .onAppear {
      target = EmojiInserter.frontTarget()
      focused = true
      model.onDismiss = { NotchShelfController.shared.dismissShelf() }
      model.onPaste = { text in
        NotchShelfController.shared.dismissShelf()
        ThunderstormController.paste(text, into: target)
      }
    }
    .onKeyPress(.downArrow) { model.move(1); return .handled }
    .onKeyPress(.upArrow) { model.move(-1); return .handled }
    .onKeyPress(.return) { model.activateSelected(); return .handled }
    .onKeyPress(phases: .down) { press in
      guard press.modifiers == .command else { return .ignored }
      if press.characters == "c" { model.copyTitleOfSelected(); return .handled }
      if let digit = Int(press.characters), (1...9).contains(digit) { model.activate(index: digit - 1); return .handled }
      return .ignored
    }
  }

  @ViewBuilder private var results: some View {
    if model.results.isEmpty && model.query.isEmpty {
      VStack(spacing: 10) {
        Text("Try typing").font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary)
        HStack(spacing: 8) {
          ForEach(Self.examples, id: \.self) { example in
            Button { model.query = example } label: { Text(example) }.buttonStyle(IslandPillStyle(compact: true))
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
              ThunderRow(result: result, index: index, selected: index == model.selection, confirming: model.confirming?.id == result.id)
                .id(index)
                .onTapGesture { model.activate(result) }
            }
            if let notice = model.notice {
              Text(notice).font(.system(size: 12)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            }
          }
        }
        .scrollIndicators(.hidden).islandBottomFade()
        .onChange(of: model.selection) { _, value in proxy.scrollTo(value) }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      Text(verbatim: model.confirming != nil ? L10n.tr("Press Return to confirm") : (model.results.indices.contains(model.selection) ? model.results[model.selection].hint : L10n.tr("Return opens")))
      Text("⌘C copies")
      Spacer()
      Text(L10n.tr("Anywhere: %@", state.shortcutText))
    }
    .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
  }
}

/// The launcher's on/off switch as an observable so the first-run card flips to the search box.
@MainActor
final class LauncherEnabledState: ObservableObject {
  static let shared = LauncherEnabledState()
  @Published private(set) var enabled: Bool
  private let settings: AppSettings

  init(settings: AppSettings = .shared) {
    self.settings = settings
    enabled = settings.thunderstormEnabled
  }

  var shortcutText: String {
    let shortcut = settings.thunderstormShortcut
    return shortcut.isSet ? shortcut.display : L10n.tr("no shortcut set")
  }

  func refresh() { enabled = settings.thunderstormEnabled }

  /// Turns the launcher on and registers its global shortcut.
  func enable() {
    settings.thunderstormEnabled = true
    ThunderstormController.shared.start()
    enabled = true
  }
}
