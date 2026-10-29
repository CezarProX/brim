import AppKit
import SwiftUI

/// The Cleaner inside the island: pick an app, tick what it left behind, confirm, and it goes to
/// the Trash. Nothing is ticked for you and nothing moves without a second, explicit confirmation.
@MainActor
struct CleanerIslandView: View {
  @ObservedObject var model: CleanerModel
  @ObservedObject var settings: CleanerEnabledState
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(model: CleanerModel, settings: CleanerEnabledState = .shared) {
    self.model = model
    self.settings = settings
  }

  var body: some View {
    Group {
      if settings.enabled { workspace } else { intro }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.chosen?.id)
    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.confirming)
  }

  // MARK: First run

  private var intro: some View {
    IslandIntroCard(
      symbol: "trash.circle.fill", tint: Color(red: 0.95, green: 0.35, blue: 0.4),
      headline: L10n.tr("Remove an app and everything it leaves behind"),
      lines: [
        ("magnifyingglass", L10n.tr("Finds the app's files in your Library, with sizes")),
        ("checkmark.circle", L10n.tr("You tick each item; nothing is chosen for you")),
        ("arrow.uturn.backward", L10n.tr("Everything goes to the Trash, so you can put it back")),
      ],
      actionTitle: L10n.tr("Turn on Cleaner"), action: { settings.enable() },
      footnote: L10n.tr("Apple's apps and Brim are never offered."))
  }

  // MARK: Workspace

  private var workspace: some View {
    VStack(spacing: 8) {
      topBar
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
      footer.frame(height: 34)
    }
    .onAppear { model.refreshIfNeeded() }
  }

  @ViewBuilder private var topBar: some View {
    if let app = model.chosen {
      HStack(spacing: 10) {
        Button { model.leaveApp() } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            Text("Apps").font(.system(size: 12.5, weight: .semibold))
          }
          .foregroundStyle(IslandInk.primary).padding(.horizontal, 10).frame(height: 28)
          .background(IslandFill.raised, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.94)).help("Back to the app list")
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 26, height: 26)
        Text(app.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
        Spacer(minLength: 0)
        if model.isRunning {
          Label("Running", systemImage: "circle.fill").font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.orange).labelStyle(.titleAndIcon)
        }
      }
      .frame(height: 30)
    } else {
      HStack(spacing: 10) {
        IslandSegmented(
          options: CleanerModel.Mode.allCases.map { ($0, $0.title) }, selection: model.mode,
          select: { model.switchMode($0) })
        if model.mode == .uninstall {
          IslandSearchField(prompt: L10n.tr("Search apps"), text: $model.search, font: .system(size: 13), height: 32, focus: $searchFocused)
        } else {
          Spacer(minLength: 0)
        }
      }
      .frame(height: 32)
    }
  }

  @ViewBuilder private var content: some View {
    if model.chosen != nil {
      leftovers
    } else if model.mode == .caches {
      caches
    } else {
      appList
    }
  }

  // MARK: Apps

  private var appList: some View {
    let apps = model.filteredApps
    return Group {
      if !model.appsLoaded {
        IslandEmptyNote(symbol: "app", text: L10n.tr("Looking for your apps…"), spinner: true)
      } else if apps.isEmpty {
        IslandEmptyNote(
          symbol: "app.dashed",
          text: model.search.isEmpty ? L10n.tr("No removable apps found in Applications.") : L10n.tr("No app matches “%@”.", model.search))
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(apps) { app in
              Button { model.choose(app) } label: {
                IslandHoverRow(height: 38) {
                  HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
                    Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(IslandInk.primary).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
                  }
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(app.name)
            }
          }
        }
        .scrollIndicators(.hidden).islandBottomFade()
      }
    }
  }

  // MARK: Leftovers

  private var leftovers: some View {
    ScrollView {
      LazyVStack(spacing: 2) {
        if let app = model.chosen { appRow(app) }
        if model.isScanning {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Looking through your Library…").font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary)
          }
          .frame(maxWidth: .infinity).padding(.top, 18)
        } else if model.items.isEmpty {
          Text("No other files found. Only the app itself can be removed.")
            .font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 14)
        }
        ForEach(model.items) { item in itemRow(item) }
      }
    }
    .scrollIndicators(.hidden).islandBottomFade()
  }

  private func appRow(_ app: InstalledApp) -> some View {
    checkRow(
      title: L10n.tr("The app itself"), subtitle: model.isRunning ? L10n.tr("Running: quit it first") : (app.url.path as NSString).abbreviatingWithTildeInPath,
      size: model.isScanning ? nil : model.appSize, on: model.includeApp, warning: model.isRunning && model.includeApp,
      isApp: true, toggle: { model.toggleApp() }, reveal: { NSWorkspace.shared.activateFileViewerSelecting([app.url]) })
  }

  private func itemRow(_ item: CleanerItem) -> some View {
    checkRow(
      title: item.leftover.url.lastPathComponent, subtitle: subtitle(item), size: item.size,
      on: model.selected.contains(item.id), warning: item.leftover.confidence == .name, isApp: false,
      toggle: { model.toggle(item) }, reveal: { model.reveal(item) })
  }

  private func subtitle(_ item: CleanerItem) -> String {
    item.leftover.confidence == .name
      ? L10n.tr("~/Library/%@ · matched by name only", item.leftover.category) : "~/Library/\(item.leftover.category)"
  }

  // MARK: Caches

  private var caches: some View {
    Group {
      if model.isScanning && model.cacheItems.isEmpty {
        IslandEmptyNote(symbol: "internaldrive", text: L10n.tr("Measuring caches…"), spinner: true)
      } else if model.cacheItems.isEmpty {
        IslandEmptyNote(symbol: "checkmark.circle", text: L10n.tr("No caches to clear."))
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(model.cacheItems) { item in
              checkRow(
                title: item.leftover.url.lastPathComponent, subtitle: L10n.tr("Rebuilt automatically by the app"), size: item.size,
                on: model.selected.contains(item.id), warning: false, isApp: false,
                toggle: { model.toggle(item) }, reveal: { model.reveal(item) })
            }
          }
        }
        .scrollIndicators(.hidden).islandBottomFade()
      }
    }
  }

  // MARK: Rows

  private func checkRow(
    title: String, subtitle: String, size: Int64?, on: Bool, warning: Bool, isApp: Bool,
    toggle: @escaping () -> Void, reveal: @escaping () -> Void
  ) -> some View {
    IslandHoverRow(selected: on, height: 42) {
      HStack(spacing: 10) {
        Button(action: toggle) {
          Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 17))
            .foregroundStyle(on ? Color.accentColor : IslandInk.tertiary).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(on ? L10n.tr("Selected") : L10n.tr("Not selected"))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 13, weight: isApp ? .semibold : .medium)).foregroundStyle(IslandInk.primary).lineLimit(1)
          Text(subtitle).font(.system(size: 11.5)).foregroundStyle(warning ? Color.orange : IslandInk.tertiary).lineLimit(1)
        }
        Spacer(minLength: 6)
        if let size {
          Text(CleanerScanner.format(size)).font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(IslandInk.secondary)
        }
        Button(action: reveal) {
          Image(systemName: "magnifyingglass.circle").font(.system(size: 15)).foregroundStyle(IslandInk.tertiary)
            .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show in Finder")
      }
    }
    .onTapGesture(perform: toggle)
  }

  // MARK: Footer

  @ViewBuilder private var footer: some View {
    if model.confirming {
      HStack(spacing: 10) {
        Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandTint.recording)
        Text(L10n.tr("Move %lld to the Trash? (%@)", model.selectionCount, CleanerScanner.format(model.selectedBytes)))
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
        Spacer(minLength: 4)
        Button("Cancel") { model.cancelMove() }.buttonStyle(IslandPillStyle())
        Button("Move to Trash") { model.confirmMove() }.buttonStyle(IslandPillStyle(prominent: true, tint: IslandTint.recording))
      }
      .padding(.horizontal, 10)
      .background(IslandTint.recording.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      HStack(spacing: 10) {
        status
        Spacer(minLength: 4)
        if model.chosen != nil || model.mode == .caches, !model.isScanning {
          if model.selectionCount == 0 {
            Button(model.mode == .caches ? L10n.tr("Select all") : L10n.tr("Select suggested")) {
              model.mode == .caches ? model.selectAll() : model.selectSuggested()
            }
            .buttonStyle(IslandPillStyle(compact: true))
            .disabled(model.mode == .uninstall && model.suggestedIDs.isEmpty)
          } else {
            Button("Clear") { model.clearSelection() }.buttonStyle(IslandPillStyle(compact: true))
            Button("Move to Trash…") { model.requestMove() }
              .buttonStyle(IslandPillStyle(prominent: true, tint: IslandTint.recording)).disabled(!model.canMove)
          }
        }
      }
    }
  }

  @ViewBuilder private var status: some View {
    if let message = model.message {
      Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(IslandInk.secondary).lineLimit(1).labelStyle(.titleAndIcon)
    } else if model.blockedByRunningApp {
      Text("Quit the app first, or untick it.").font(.system(size: 12.5)).foregroundStyle(Color.orange)
    } else if model.selectionCount > 0 {
      Text(L10n.tr("%lld selected · %@", model.selectionCount, CleanerScanner.format(model.selectedBytes)))
        .font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(IslandInk.secondary)
    } else {
      Text(model.chosen != nil || model.mode == .caches
        ? L10n.tr("Nothing is ticked. Everything goes to the Trash.") : L10n.tr("Pick an app to see what it leaves behind."))
        .font(.system(size: 12.5)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
    }
  }
}

/// The Cleaner's on/off switch as an observable, so the first-run card flips to the workspace.
@MainActor
final class CleanerEnabledState: ObservableObject {
  static let shared = CleanerEnabledState()
  @Published private(set) var enabled: Bool
  private let settings: AppSettings

  init(settings: AppSettings = .shared) {
    self.settings = settings
    enabled = settings.cleanerEnabled
  }

  func enable() {
    settings.cleanerEnabled = true
    enabled = true
  }

  /// Re-reads the setting (it can change in the Settings window while the island is open).
  func refresh() { enabled = settings.cleanerEnabled }
}

/// Owns the Cleaner's model for as long as the widget is open.
@MainActor
struct CleanerIslandHost: View {
  @StateObject private var model = CleanerModel()

  var body: some View {
    CleanerIslandView(model: model)
      .onAppear {
        CleanerEnabledState.shared.refresh()
        model.switchMode(CleanerController.shared.consumePendingMode())
      }
  }
}
