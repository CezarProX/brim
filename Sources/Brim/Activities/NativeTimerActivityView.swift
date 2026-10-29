import SwiftUI

@MainActor
struct NativeTimerActivityView: View {
    let timer: NativeTimerActivity
    @ObservedObject private var model: NativeTimerModel

    init(timer: NativeTimerActivity) {
        self.init(timer: timer, model: .shared)
    }

    init(timer: NativeTimerActivity, model: NativeTimerModel) {
        self.timer = timer
        self.model = model
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack(spacing: IslandSpace.m) {
                if model.controlCapability == .accessibilityPermissionRequired {
                    Button("Allow") { model.requestAccessibilityPermission() }
                        .buttonStyle(IslandPillStyle(prominent: true, tint: IslandTint.timer))
                        .help("Allow Accessibility access to control Clock")
                } else {
                    IslandControlButton(title: timer.isPaused ? "Resume timer" : "Pause timer",
                                        symbol: timer.isPaused ? "play.fill" : "pause.fill",
                                        role: .tinted(IslandTint.timer), showsTitle: false, diameter: 40) {
                        Task {
                            if timer.isPaused { await model.resume(expectedID: timer.id) }
                            else { await model.pause(expectedID: timer.id) }
                        }
                    }
                    .disabled(model.isWorking)
                    IslandControlButton(title: "Cancel timer", symbol: "xmark", showsTitle: false, diameter: 40) {
                        Task { await model.cancel(expectedID: timer.id) }
                    }
                    .disabled(model.isWorking)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(status).font(IslandFont.label)
                        .foregroundStyle(model.controlError == nil ? IslandTint.timer.opacity(0.8) : Color.red)
                        .lineLimit(1)
                    Text(CompactTimerReadout.format(remaining))
                        .font(IslandFont.display).monospacedDigit()
                        .foregroundStyle(IslandTint.timer)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .padding(.vertical, IslandSpace.s)
        }
    }

    private var status: String {
        if let error = model.controlError { return error }
        if model.isWorking { return "Updating Clock…" }
        return timer.isPaused ? "Paused" : timer.title
    }
}
