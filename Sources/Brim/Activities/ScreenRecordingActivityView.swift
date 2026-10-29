import SwiftUI

struct ScreenRecordingActivityView: View {
    @ObservedObject var model: ScreenRecordingModel
    var namespace: Namespace.ID?

    var body: some View {
        HStack(spacing: IslandSpace.m) {
            if let namespace {
                RecordingStatusDot().matchedGeometryEffect(id: "recording-dot", in: namespace)
            } else {
                RecordingStatusDot()
            }
            VStack(alignment: .leading, spacing: 2) {
                if let paused = model.activeRecording?.pausedElapsed {
                    Text(Duration.seconds(paused).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(IslandInk.secondary)
                } else if let beganAt = model.activeRecording?.beganAt {
                    Text(beganAt, style: .timer)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(IslandTint.recording)
                        .accessibilityLabel("Time since recording was detected")
                }
                Text(status)
                    .font(IslandFont.label)
                    .foregroundStyle(model.stopError == nil ? IslandInk.tertiary
                        : Color(red: 1, green: 0.42, blue: 0.38))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .help(model.stopError ?? "")
                    .accessibilityLabel(model.stopError ?? status)
                    .accessibilityIdentifier(model.stopError == nil ? "screen-recording-status" : "screen-recording-stop-error")
            }
            Spacer()
            if model.supportsPause, !model.isWorking {
                Button { model.togglePause() } label: {
                    Image(systemName: model.activeRecording?.pausedElapsed == nil ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(IslandInk.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(IslandPressStyle(pressedScale: 0.88))
                .help(model.activeRecording?.pausedElapsed == nil ? "Pause recording" : "Resume recording")
                .accessibilityIdentifier("screen-recording-pause")
            }
            Button {
                Task { await model.stopRecording() }
            } label: {
                ZStack {
                    Circle().fill(IslandTint.recording.opacity(0.2))
                    if model.isWorking {
                        ProgressView().controlSize(.small).tint(.red)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(IslandTint.recording)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.88))
            .disabled(model.isWorking)
            .help("Stop and save recording")
            .accessibilityLabel(model.isWorking ? "Stopping screen recording" : "Stop and save screen recording")
            .accessibilityIdentifier("screen-recording-stop")
        }
        .padding(.top, IslandSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        if let error = model.stopError {
            return error == ScreenRecordingStopError.accessibilityPermissionRequired.localizedDescription
                ? "Accessibility access required" : "Couldn’t stop recording"
        }
        if model.activeRecording?.pausedElapsed != nil { return L10n.tr("Paused") }
        return model.isWorking ? "Saving…" : "Screen Recording"
    }
}
