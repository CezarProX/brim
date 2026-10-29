import SwiftUI

/// Leading glyphs and trailing values for the live activities the feature packages added to the
/// closed island: the download ring, the Pomodoro ring and the Xcode build clock.
@MainActor
enum CompactActivityHooks {
  /// The leading wing for an activity that draws its own glyph; nil uses the shell's default.
  @ViewBuilder
  static func glyph(_ activity: IslandActivity, center: ActivityCenter) -> some View {
    switch activity {
    case .download:
      if let snapshot = center.downloads.active { DownloadCompactLeading(snapshot: snapshot) }
    case .focus:
      PomodoroCompactRing(model: center.focus, showsTime: false)
    case .build:
      XcodeBuildCompactGlyph(status: center.builds.status)
    case .privacy:
      if let privacy = center.privacy {
        Image(systemName: privacy.symbol).font(.system(size: CompactLayout.glyphSize, weight: .semibold))
          .foregroundStyle(privacy == .microphone ? Color.orange : Color.green)
      }
    default:
      EmptyView()
    }
  }

  static func drawsGlyph(_ activity: IslandActivity) -> Bool {
    [.download, .focus, .build, .privacy].contains(activity)
  }

  /// The trailing wing for an activity with a custom readout; nil uses the shell's text value.
  @ViewBuilder
  static func trailing(_ activity: IslandActivity, center: ActivityCenter) -> some View {
    switch activity {
    case .download:
      if let snapshot = center.downloads.active { DownloadCompactTrailing(snapshot: snapshot) }
    case .build:
      XcodeBuildCompactValue(model: center.builds)
    case .dictation:
      DictationCompactTrailing(model: center.dictation)
    default:
      EmptyView()
    }
  }

  static func drawsTrailing(_ activity: IslandActivity) -> Bool {
    [.download, .build, .dictation].contains(activity)
  }
}

/// Hammer while building, a check or a cross once the build is done.
private struct XcodeBuildCompactGlyph: View {
  let status: XcodeBuildStatus

  var body: some View {
    Group {
      switch status {
      case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
      default:
        Image(systemName: "hammer.fill").foregroundStyle(Color(red: 0.36, green: 0.66, blue: 1))
          .symbolEffect(.pulse, options: .repeating)
      }
    }
    .font(.system(size: CompactLayout.glyphSize, weight: .semibold))
    .contentTransition(.symbolEffect(.replace))
  }
}

/// Elapsed clock while building, then the duration or the error count.
private struct XcodeBuildCompactValue: View {
  @ObservedObject var model: XcodeBuildModel

  var body: some View {
    Group {
      if case .building(_, let since) = model.status {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let elapsed = context.date.timeIntervalSince(since)
          // An estimate from how long the previous build took, when there is one.
          if let percent = BuildProgress.percent(elapsed: elapsed, typical: model.typicalDuration) {
            Text("\(percent)%")
          } else {
            Text(XcodeBuildDetector.clock(elapsed))
          }
        }
      } else if let text = XcodeBuildCompactView.resultText(model.status) {
        Text(text)
      }
    }
    .font(CompactLayout.labelFont).monospacedDigit().foregroundStyle(IslandInk.primary)
    .lineLimit(1).contentTransition(.numericText())
  }
}
