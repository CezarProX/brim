import ApplicationServices
import SwiftUI

/// Dictation the way the system does it: one big microphone, the words appearing beside it, then
/// Copy or Insert. Permissions are asked when the microphone is pressed, and a refusal says which
/// switch to turn on and opens it.
struct DictationActivityView: View {
  @ObservedObject var model: DictationModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isLive: Bool { model.isRecording || model.isStarting }
  private var tint: Color { isLive ? IslandTint.recording : IslandTint.color(for: .dictation) }

  var body: some View {
    HStack(alignment: .top, spacing: IslandSpace.l) {
      micButton
      VStack(alignment: .leading, spacing: IslandSpace.s) {
        statusLine
        transcriptBox
        actions
        if let issue = model.permissionIssue { permissionRow(issue) } else if let hint = insertHint { hintRow(hint) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.isRecording)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.errorMessage)
  }

  // MARK: Microphone

  private var micButton: some View {
    VStack(spacing: 6) {
      Button {
        if isLive {
          model.stop()
        } else {
          Task { await model.start() }
        }
      } label: {
        ZStack {
          Circle().fill(tint)
          if model.isRecording {
            PlaybackWaveform(isPlaying: !reduceMotion, colored: true, tint: .white).frame(width: 32, height: 26)
          } else if model.isStarting {
            ProgressView().controlSize(.small).tint(.white)
          } else {
            Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
          }
        }
        .frame(width: 76, height: 76)
        .shadow(color: tint.opacity(isLive ? 0.55 : 0), radius: 14)
        .contentShape(Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.9))
      .accessibilityLabel(isLive ? "Stop" : "Start")
      .accessibilityIdentifier(isLive ? "dictation-stop" : "dictation-start")
      Text(isLive ? "Stop" : (model.transcript.isEmpty ? "Start" : "Again"))
        .font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
    }
    .frame(width: 84)
  }

  private var statusLine: some View {
    HStack(spacing: 6) {
      Circle().fill(model.isRecording ? tint : IslandInk.tertiary).frame(width: 7, height: 7)
      Text(statusText).font(IslandFont.body).foregroundStyle(model.isRecording ? tint : IslandInk.secondary)
    }
  }

  private var statusText: String {
    if model.isStarting { return L10n.tr("Waiting for permission…") }
    if model.isRecording { return L10n.tr("Listening… speak now") }
    return L10n.tr("Ready · runs on this Mac, nothing is uploaded")
  }

  // MARK: Words

  private var transcriptBox: some View {
    ScrollView {
      Text(model.transcript.isEmpty ? placeholder : model.transcript)
        .font(.system(size: model.transcript.isEmpty ? 13 : 16, weight: .regular))
        .foregroundStyle(model.transcript.isEmpty ? IslandInk.tertiary : IslandInk.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentTransition(.opacity)
    }
    .scrollIndicators(.hidden)
    .padding(IslandSpace.m)
    .frame(height: 120)
    .glassCard(radius: IslandRadius.medium)
  }

  private var placeholder: String {
    if model.isStarting { return L10n.tr("Allow the Microphone and Speech Recognition when macOS asks.") }
    if model.isRecording { return L10n.tr("Start speaking…") }
    return L10n.tr("Click into a text field in any app, press the microphone and talk. Your words appear here, ready to insert or copy. macOS asks for Microphone and Speech Recognition the first time.")
  }

  // MARK: Actions

  private var actions: some View {
    HStack(spacing: IslandSpace.s) {
      Button(action: model.copy) { Label("Copy", systemImage: "doc.on.doc") }
        .buttonStyle(AppSecondaryButtonStyle())
        .disabled(!model.canCopy)
        .accessibilityIdentifier("dictation-copy")
      Button { try? model.insert() } label: { Label("Insert", systemImage: "text.insert") }
        .buttonStyle(AppSecondaryButtonStyle())
        .disabled(!model.canInsert)
        .help(model.hasInsertionTarget
          ? "Insert into the text field focused when dictation started"
          : "Start dictation while an editable text field is focused")
        .accessibilityIdentifier("dictation-insert")
      if let message = model.errorMessage ?? model.lastActionMessage {
        Text(message)
          .font(IslandFont.body)
          .foregroundStyle(model.errorMessage == nil ? IslandInk.secondary : IslandTint.recording)
          .lineLimit(2)
          .accessibilityIdentifier(model.errorMessage == nil ? "dictation-status" : "dictation-error")
          .transition(.islandDrop)
      }
      Spacer(minLength: 0)
    }
  }

  private func permissionRow(_ issue: DictationPermissionIssue) -> some View {
    HStack(spacing: IslandSpace.s) {
      Button(issue == .microphone ? "Open Microphone Settings" : "Open Speech Recognition Settings") {
        NSWorkspace.shared.open(issue.settingsURL)
      }
      .buttonStyle(AppPrimaryButtonStyle(tint: IslandTint.recording))
      Text("Switch Brim on, then press the microphone again.")
        .font(IslandFont.body).foregroundStyle(IslandInk.tertiary).lineLimit(2)
    }
  }

  /// Why Insert is greyed out, when there is a reason worth telling.
  private var insertHint: String? {
    guard !model.isRecording, !model.isStarting, !model.transcript.isEmpty, !model.hasInsertionTarget else { return nil }
    if !AXIsProcessTrusted() { return L10n.tr("Insert needs Accessibility access. Copy works without it.") }
    return L10n.tr("Insert needs a text field to be focused when you press the microphone. Copy works anywhere.")
  }

  private func hintRow(_ hint: String) -> some View {
    Text(hint).font(IslandFont.body).foregroundStyle(IslandInk.tertiary).lineLimit(2)
  }
}
