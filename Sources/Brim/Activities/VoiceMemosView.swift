import SwiftUI

/// Voice Memo: record with one button, then read the words back. Recordings sit in a list; the
/// newest opens right after recording with a Transcribe button, and every row can be played,
/// transcribed, copied, dragged out or moved to the Trash.
struct VoiceMemosView: View {
  @ObservedObject var model: VoiceRecorderModel
  @State private var expanded: URL?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(model: VoiceRecorderModel, expanded: URL? = nil) {
    self.model = model
    _expanded = State(initialValue: expanded)
  }

  var body: some View {
    VStack(spacing: IslandSpace.s) {
      if model.isRecording {
        recording
      } else if model.memos.isEmpty {
        empty
      } else {
        list
      }
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isRecording)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: expanded)
    .onChange(of: model.isRecording) { _, recording in
      // The memo that was just recorded opens, so Transcribe is one click away.
      if !recording { expanded = model.memos.first?.url }
    }
  }

  // MARK: States

  private var empty: some View {
    VStack(spacing: 6) {
      Spacer(minLength: 0)
      recordButton(size: 56)
      Text("Tap to record").font(IslandFont.title).foregroundStyle(IslandInk.primary).padding(.top, 4)
      Text("Recordings stay on this Mac. Turn any of them into text with one click, on device.")
        .font(IslandFont.body).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
      statusMessage
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private var recording: some View {
    VStack(spacing: IslandSpace.s) {
      Spacer(minLength: 0)
      if let started = model.recordingStarted {
        Text(started, style: .timer)
          .font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
          .foregroundStyle(IslandTint.recording)
      }
      LevelMeter(level: model.level).frame(height: 40)
      HStack(spacing: IslandSpace.s) {
        recordButton(size: 48)
        Text("Recording… tap to stop and save").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .transition(.islandContent)
  }

  private var list: some View {
    HStack(alignment: .top, spacing: IslandSpace.m) {
      VStack(spacing: IslandSpace.s) {
        recordButton(size: 56)
        Text("Record").font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
        Text(model.memos.count == 1 ? "1 recording" : "\(model.memos.count) recordings")
          .font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
        statusMessage
        Spacer(minLength: 0)
      }
      .frame(width: 130)
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(model.memos) { memo in
            MemoRow(memo: memo, model: model, expanded: expanded == memo.url) {
              expanded = expanded == memo.url ? nil : memo.url
            }
          }
        }
      }
      .scrollIndicators(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  /// The last thing that happened, with a way to the right Settings pane when a permission is off.
  @ViewBuilder private var statusMessage: some View {
    if let message = model.message {
      VStack(spacing: 6) {
        Text(message).font(IslandFont.body).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        if let issue = model.permissionIssue {
          Button(issue == .microphone ? "Open Microphone Settings" : "Open Speech Recognition Settings") {
            NSWorkspace.shared.open(issue.settingsURL)
          }
          .buttonStyle(AppPrimaryButtonStyle(tint: IslandTint.recording))
        }
      }
    }
  }

  private func recordButton(size: CGFloat) -> some View {
    Button {
      Task { await model.toggleRecording() }
    } label: {
      ZStack {
        Circle().stroke(.white.opacity(0.55), lineWidth: size * 0.065).padding(size * 0.0325)
        RoundedRectangle(cornerRadius: model.isRecording ? size * 0.11 : size * 0.4, style: .continuous)
          .fill(IslandTint.recording)
          .frame(width: model.isRecording ? size * 0.38 : size * 0.78, height: model.isRecording ? size * 0.38 : size * 0.78)
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
      .animation(.spring(duration: 0.3, bounce: 0.3), value: model.isRecording)
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .accessibilityLabel(model.isRecording ? "Stop recording" : "Record")
  }
}

private struct MemoRow: View {
  let memo: VoiceMemo
  @ObservedObject var model: VoiceRecorderModel
  let expanded: Bool
  let toggle: () -> Void

  private var isPlaying: Bool { model.playing == memo.url }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: IslandSpace.m) {
        Button { model.togglePlayback(memo) } label: {
          Image(systemName: isPlaying ? "stop.fill" : "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isPlaying ? Color.black : IslandInk.primary)
            .frame(width: 32, height: 32)
            .background(isPlaying ? Color.white : IslandFill.raised, in: Circle())
            .contentShape(Circle())
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel(isPlaying ? "Stop" : "Play")
        Button(action: toggle) {
          HStack(spacing: IslandSpace.s) {
            VStack(alignment: .leading, spacing: 1) {
              Text(memo.date, format: .dateTime.weekday(.wide).hour().minute())
                .font(IslandFont.headline).foregroundStyle(IslandInk.primary)
              Text(verbatim: summary).font(IslandFont.body).foregroundStyle(IslandInk.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.transcribing == memo.url { ProgressView().controlSize(.small) }
            Text(Duration.seconds(memo.duration).formatted(.time(pattern: .minuteSecond)))
              .font(IslandFont.body).monospacedDigit().foregroundStyle(IslandInk.secondary)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandInk.tertiary)
              .rotationEffect(.degrees(expanded ? 180 : 0))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      if expanded { details }
    }
    .padding(.vertical, 6).padding(.horizontal, 8)
    .background(expanded ? IslandFill.subtle : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .contextMenu {
      Button(memo.transcript == nil ? "Transcribe" : "Transcribe Again") { Task { await model.transcribe(memo) } }
      if memo.transcript != nil { Button("Copy Transcript") { model.copyTranscript(memo) } }
      Button("Show in Finder") { model.reveal(memo) }
      Divider()
      Button("Move to Trash", role: .destructive) { model.delete(memo) }
    }
    .onDrag { NSItemProvider(contentsOf: memo.url) ?? NSItemProvider() }
  }

  private var summary: String {
    if let transcript = memo.transcript, !transcript.isEmpty { return transcript }
    if model.transcribing == memo.url { return L10n.tr("Transcribing…") }
    return memo.date.formatted(date: .abbreviated, time: .omitted)
  }

  @ViewBuilder private var details: some View {
    if let transcript = memo.transcript, !transcript.isEmpty {
      ScrollView {
        Text(verbatim: transcript).font(.system(size: 13)).foregroundStyle(IslandInk.primary)
          .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden).frame(maxHeight: 72)
    } else if memo.transcript != nil {
      Text("No speech found in this recording.").font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
    }
    HStack(spacing: IslandSpace.s) {
      if memo.transcript?.isEmpty == false {
        Button { model.copyTranscript(memo) } label: { Label("Copy", systemImage: "doc.on.doc") }
          .buttonStyle(AppPrimaryButtonStyle(tint: IslandTint.recording))
      }
      Button { Task { await model.transcribe(memo) } } label: {
        Label(memo.transcript == nil ? "Transcribe" : "Again", systemImage: "text.bubble")
      }
      .buttonStyle(memo.transcript == nil ? AnyButtonStyle(AppPrimaryButtonStyle(tint: IslandTint.recording)) : AnyButtonStyle(AppSecondaryButtonStyle()))
      .disabled(model.transcribing != nil)
      Button { model.reveal(memo) } label: { Label("Finder", systemImage: "folder") }
        .buttonStyle(AppSecondaryButtonStyle())
      Spacer(minLength: 0)
      AppIconButton(symbol: "trash", label: "Move to Trash") { model.delete(memo) }
    }
  }
}

/// Lets one button choose between two styles at run time.
private struct AnyButtonStyle: ButtonStyle {
  private let make: (Configuration) -> AnyView
  init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
  func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

private struct LevelMeter: View {
  let level: Double

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 20)) { context in
      Canvas { graphics, size in
        let bars = 48
        let width = size.width / CGFloat(bars) * 0.55
        for index in 0..<bars {
          let phase = context.date.timeIntervalSinceReferenceDate * 6 + Double(index) * 0.55
          let height = max(3, size.height * CGFloat(level) * CGFloat(0.45 + 0.55 * abs(sin(phase))))
          let x = CGFloat(index) * size.width / CGFloat(bars)
          graphics.fill(
            Path(roundedRect: CGRect(x: x, y: (size.height - height) / 2, width: width, height: height), cornerRadius: width / 2),
            with: .color(IslandTint.recording.opacity(0.9)))
        }
      }
    }
    .accessibilityHidden(true)
  }
}
