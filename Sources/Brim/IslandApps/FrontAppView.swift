import SwiftUI

/// Front App, opened: who is in front, how many windows it has, one-tap Hide / Quit / Force Quit,
/// and the apps you used most recently to jump straight back to.
struct FrontAppView: View {
  @ObservedObject var model: FrontAppModel
  @ObservedObject var workspace: WorkspaceActivityModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      if let app = model.front {
        identity(app)
        actions(app)
        switcher(app)
      } else {
        empty
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1), value: model.front?.processIdentifier)
    .onAppear { model.attach() }
    .onDisappear { model.detach() }
  }

  // MARK: Identity

  private func identity(_ app: NSRunningApplication) -> some View {
    HStack(spacing: IslandSpace.m) {
      Group {
        if let icon = app.icon {
          Image(nsImage: icon).resizable().interpolation(.high)
        } else {
          Image(systemName: "app.dashed").resizable().foregroundStyle(IslandInk.tertiary)
        }
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text(app.localizedName ?? L10n.tr("Application")).font(.system(size: 17, weight: .semibold)).lineLimit(1)
        Text(details(app)).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      Spacer(minLength: IslandSpace.s)
      Button { model.revealFront() } label: {
        Image(systemName: "folder").font(.system(size: 13, weight: .semibold))
          .frame(width: 32, height: 32)
          .background(IslandFill.raised, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.9))
      .help(L10n.tr("Show in Finder"))
      .accessibilityLabel(L10n.tr("Show in Finder"))
    }
  }

  private func details(_ app: NSRunningApplication) -> String {
    var parts: [String] = []
    parts.append(model.windowCount == 1 ? L10n.tr("1 window") : L10n.tr("%lld windows", model.windowCount))
    if let open = FrontAppModel.openDuration(since: app.launchDate) { parts.append(open) }
    return parts.joined(separator: " · ")
  }

  // MARK: Actions

  private func actions(_ app: NSRunningApplication) -> some View {
    let armed = model.forceQuitArmed == app.processIdentifier
    let canQuit = model.canQuitFront
    return HStack(spacing: IslandSpace.s) {
      IslandAppButton(title: L10n.tr("Hide"), symbol: "eye.slash") { model.hideFront() }
        .disabled(FrontAppModel.isProtected(bundleID: app.bundleIdentifier))
      IslandAppButton(title: L10n.tr("Hide Others"), symbol: "rectangle.on.rectangle.slash") { model.hideOthers() }
      IslandAppButton(title: L10n.tr("Quit"), symbol: "power") { model.quitFront() }
        .disabled(!canQuit)
      IslandAppButton(
        title: armed ? L10n.tr("Confirm?") : L10n.tr("Force Quit"),
        symbol: "exclamationmark.octagon", style: .destructive
      ) { model.forceQuitFront() }
      .disabled(!canQuit)
    }
  }

  // MARK: Switcher

  private func switcher(_ front: NSRunningApplication) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Recent apps").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        Spacer(minLength: 0)
        Text("Show in the island when idle").font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
        Toggle("Show in the island when idle", isOn: Binding(
          get: { workspace.workspaceEnabled }, set: workspace.setWorkspaceEnabled))
          .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.green)
      }
      HStack(spacing: 6) {
        ForEach(model.recents) { entry in
          let current = entry.id == front.processIdentifier
          Button { model.activate(entry) } label: {
            Group {
              if let icon = entry.icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            .frame(width: 36, height: 36)
            .background(current ? IslandFill.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
          .buttonStyle(IslandPressStyle(pressedScale: 0.9))
          .help(entry.name)
          .accessibilityLabel(entry.name)
          .accessibilityAddTraits(current ? .isSelected : [])
        }
        Spacer(minLength: 0)
      }
    }
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Spacer(minLength: 0)
      Image(systemName: "macwindow").font(.system(size: 30, weight: .light)).foregroundStyle(IslandInk.secondary)
      Text("No app in front yet").font(.system(size: 13, weight: .semibold))
      Text("Click any app and it shows up here.").font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }
}
