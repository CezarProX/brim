import AppKit
import SwiftUI

/// Live Xcode build activity. `XcodeBuildCompactView` is the pill content (hammer, project,
/// timer); `XcodeBuildCard` is the open-island card.
struct XcodeBuildCompactView: View {
  @ObservedObject var model: XcodeBuildModel

  var body: some View {
    HStack(spacing: 6) {
      icon(model.status, size: 13)
      if case .building(_, let since) = model.status {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(XcodeBuildDetector.clock(context.date.timeIntervalSince(since)))
            .font(IslandFont.caption).monospacedDigit().foregroundStyle(IslandInk.primary).fixedSize()
            .contentTransition(.numericText())
        }
      } else if let text = Self.resultText(model.status) {
        Text(text).font(IslandFont.caption).foregroundStyle(IslandInk.primary).monospacedDigit()
      }
    }
  }

  static func resultText(_ status: XcodeBuildStatus) -> String? {
    switch status {
    case .succeeded(_, let duration, _): duration.map(XcodeBuildDetector.clock)
    case .failed(_, _, let errors): "\(errors)"
    default: nil
    }
  }

  @ViewBuilder fileprivate func icon(_ status: XcodeBuildStatus, size: CGFloat) -> some View {
    switch status {
    case .building:
      Image(systemName: "hammer.fill").font(.system(size: size, weight: .semibold)).foregroundStyle(.blue)
        .symbolEffect(.pulse, options: .repeating)
    case .succeeded: Image(systemName: "checkmark.circle.fill").font(.system(size: size, weight: .semibold)).foregroundStyle(.green)
    case .failed: Image(systemName: "xmark.octagon.fill").font(.system(size: size, weight: .semibold)).foregroundStyle(.red)
    case .idle: Image(systemName: "hammer").font(.system(size: size)).foregroundStyle(IslandInk.tertiary)
    }
  }
}

struct XcodeBuildCard: View {
  @ObservedObject var model: XcodeBuildModel
  /// Island app: shows the one-line purpose under the card's title row.
  var showsSubtitle = true

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: IslandSpace.l) {
        badge
        VStack(alignment: .leading, spacing: 3) {
          Text(headline).font(IslandFont.title).foregroundStyle(IslandInk.primary)
          if let name = projectLine {
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(IslandInk.secondary).lineLimit(1)
          }
          detail.font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: IslandSpace.s)
        action
      }
      .padding(IslandSpace.l)
      .islandAppCardSurface()
    }
  }

  // MARK: Pieces

  private var badge: some View {
    ZStack {
      Circle().fill(tint.opacity(0.18)).frame(width: 64, height: 64)
      if live == nil, model.watching, let last = model.last {
        Image(systemName: last.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
          .font(.system(size: 24, weight: .semibold)).foregroundStyle(tint.opacity(0.85))
      } else if !model.watching {
        Image(systemName: "eye.slash").font(.system(size: 22, weight: .medium)).foregroundStyle(IslandInk.tertiary)
      } else {
        XcodeBuildCompactView(model: model).fixedSize().scaleEffect(1.3)
      }
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder private var action: some View {
    if !model.watching {
      Button { model.enable() } label: { Label("Turn on", systemImage: "power") }
        .buttonStyle(IslandAppPillStyle(prominent: true, tint: .blue))
        .help("Start watching Xcode's build logs")
    } else if Self.xcodeURL != nil {
      Button { Self.openXcode() } label: { Label("Open Xcode", systemImage: "hammer") }
        .buttonStyle(IslandAppPillStyle())
    }
  }

  /// The running or just-finished build, nil when idle.
  private var live: XcodeBuildStatus? { model.status == .idle ? nil : model.status }

  private var tint: Color {
    switch model.status {
    case .building: return .blue
    case .succeeded: return .green
    case .failed: return .red
    case .idle:
      guard model.watching else { return .gray }
      return model.last.map { $0.succeeded ? .green : .red } ?? .gray
    }
  }

  private var projectLine: String? {
    guard model.watching else { return nil }
    return model.status.project ?? model.last?.project
  }

  private var headline: String {
    guard model.watching else { return L10n.tr("Build watching is off") }
    switch model.status {
    case .building: return L10n.tr("Building")
    case .succeeded: return L10n.tr("Build succeeded")
    case .failed: return L10n.tr("Build failed")
    case .idle:
      guard let last = model.last else { return L10n.tr("No build running") }
      return last.succeeded ? L10n.tr("Last build succeeded") : L10n.tr("Last build failed")
    }
  }

  @ViewBuilder private var detail: some View {
    if !model.watching {
      Text("Turn it on to follow builds live. Brim reads only the build summaries Xcode writes, never your code.")
    } else {
      switch model.status {
      case .building(_, let since):
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(L10n.tr("Running for %@", XcodeBuildDetector.clock(context.date.timeIntervalSince(since))))
        }
      case .succeeded, .failed:
        Text(Self.summary(for: model.status))
      case .idle:
        if let last = model.last {
          Text(Self.summary(last: last))
        } else if model.scanned && !model.foundBuildLogs {
          Text("No Xcode builds on this Mac yet. Build a project in Xcode and it shows up here.")
        } else if model.scanned {
          Text("Start a build in Xcode or xcodebuild and it shows up here.")
        } else {
          Text("Looking for Xcode builds…")
        }
      }
    }
  }

  // MARK: Text (static so tests can check it)

  static func summary(for status: XcodeBuildStatus) -> String {
    switch status {
    case .succeeded(_, let duration, let warnings):
      return [duration.map { L10n.tr("Took %@", XcodeBuildDetector.clock($0)) }, warnings > 0 ? warningsText(warnings) : nil]
        .compactMap { $0 }.joined(separator: " · ")
    case .failed(_, let duration, let errors):
      return [duration.map { L10n.tr("After %@", XcodeBuildDetector.clock($0)) }, errorsText(errors)].compactMap { $0 }.joined(separator: " · ")
    default: return ""
    }
  }

  static func summary(last: XcodeLastBuild, now: Date = .now) -> String {
    var parts: [String] = []
    if let duration = last.duration { parts.append(XcodeBuildDetector.clock(duration)) }
    if !last.succeeded { parts.append(errorsText(max(1, last.errors))) }
    if last.warnings > 0 { parts.append(warningsText(last.warnings)) }
    if let finished = last.finished {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      parts.append(formatter.localizedString(for: finished, relativeTo: now))
    }
    return parts.joined(separator: " · ")
  }

  private static func errorsText(_ count: Int) -> String {
    count == 1 ? L10n.tr("1 error") : L10n.tr("%lld errors", count)
  }

  private static func warningsText(_ count: Int) -> String {
    count == 1 ? L10n.tr("1 warning") : L10n.tr("%lld warnings", count)
  }

  /// Launch Services first; /Applications/Xcode.app when it doesn't know the bundle id.
  private static var xcodeURL: URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") { return url }
    let fallback = URL(fileURLWithPath: "/Applications/Xcode.app")
    return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
  }

  private static func openXcode() {
    guard let url = xcodeURL else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }
}

private extension View {
  func islandAppCardSurface() -> some View {
    glassCard(radius: IslandRadius.medium)
  }
}

struct XcodeBuildsSettingsSection: View {
  @State private var enabled = AppSettings.shared.xcodeBuildsEnabled

  var body: some View {
    SettingsSection("Xcode Builds") {
      Toggle("Show Xcode build progress and results in the island", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.xcodeBuildsEnabled = value
          value ? XcodeBuildModel.shared.start() : XcodeBuildModel.shared.stop()
        }
      Text("Brim watches Xcode’s build logs in ~/Library/Developer/Xcode/DerivedData and checks for xcodebuild. It reads only file dates and the build summary Xcode writes there, and never opens your source.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
