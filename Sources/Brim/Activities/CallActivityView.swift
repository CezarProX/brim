import AppKit
import SwiftUI

struct CallActivityView: View {
    @ObservedObject var model: CallActivityModel
    var embedded = false
    var onConfirmationChange: (Bool) -> Void = { _ in }
    @ObservedObject private var microphones = MicrophoneMuteController.shared
    @State private var confirmingLeave = false
    @State private var leaveCallID: UUID?
    @State private var confirmingScreenShare = false
    @State private var screenShareCallID: UUID?

    var body: some View {
        Group {
            if let call = model.activeCall { active(call) } else { empty }
        }
        .padding(embedded ? 0 : 18)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: embedded ? 260 : 220, alignment: .top)
        .foregroundStyle(.white)
        .onChange(of: confirmingLeave) { _, _ in publishConfirmationState() }
        .onChange(of: confirmingScreenShare) { _, _ in publishConfirmationState() }
        .onDisappear { onConfirmationChange(false) }
        .onChange(of: model.activeCall?.id) { _, _ in
            confirmingLeave = false
            leaveCallID = nil
            confirmingScreenShare = false
            screenShareCallID = nil
        }
        .confirmationDialog("Leave this call?", isPresented: $confirmingLeave) {
            Button("Leave call", role: .destructive) {
                if let leaveCallID { model.leave(expectedID: leaveCallID) }
                leaveCallID = nil
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Start screen sharing?", isPresented: $confirmingScreenShare) {
            Button("Start sharing") {
                if let screenShareCallID { model.toggleScreenShare(expectedID: screenShareCallID) }
                screenShareCallID = nil
            }
            Button("Cancel", role: .cancel) { screenShareCallID = nil }
        } message: {
            Text("Brim will press the screen-sharing control currently exposed by the call app.")
        }
    }

    private func active(_ call: CallActivity) -> some View {
        VStack(alignment: .leading, spacing: IslandSpace.xl) {
            HStack(spacing: IslandSpace.m) {
                appIcon(for: call)
                VStack(alignment: .leading, spacing: 3) {
                    Text(call.title)
                        .font(IslandFont.title)
                        .lineLimit(2)
                    Text(call.appName)
                        .font(IslandFont.label)
                        .foregroundStyle(IslandInk.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if isMuted(call) { MutedBadge() }
                systemMuteButton
                Text(call.beganAt, style: .timer)
                    .monospacedDigit()
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandTint.call)
                    .help("Time since Brim detected the call")
            }
            HStack(spacing: IslandSpace.l) {
                Spacer(minLength: 0)
                control(call.isMuted == true ? "Unmute" : "Mute",
                        icon: call.isMuted == true ? "mic.slash.fill" : "mic.fill",
                        enabled: model.canToggleMute, active: call.isMuted.map(!), action: model.toggleMute)
                control(call.isCameraOn == true ? "Camera off" : "Camera on",
                        icon: call.isCameraOn == true ? "video.fill" : "video.slash.fill",
                        enabled: model.canToggleCamera, active: call.isCameraOn, action: model.toggleCamera)
                control(call.isScreenSharing == true ? "Stop share" : "Share",
                        icon: call.isScreenSharing == true ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                        enabled: model.canToggleScreenShare, active: call.isScreenSharing) {
                    if call.isScreenSharing == true {
                        model.toggleScreenShare(expectedID: call.id)
                    } else {
                        screenShareCallID = call.id
                        confirmingScreenShare = true
                    }
                }
                control("Open app", icon: "arrow.up.forward.app", enabled: true, active: nil, action: model.openCall)
                control("Leave", icon: "phone.down.fill", enabled: model.canLeave, destructive: true) {
                    leaveCallID = call.id
                    confirmingLeave = true
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func isMuted(_ call: CallActivity) -> Bool { call.isMuted == true || microphones.isMuted }

    /// Mutes every microphone on the Mac, whichever app is using it.
    private var systemMuteButton: some View {
        Button { model.toggleSystemMute() } label: {
            Image(systemName: microphones.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(microphones.isMuted ? Color.red : IslandInk.secondary)
                .frame(width: 26, height: 26).background(IslandFill.raised, in: Circle())
        }
        .buttonStyle(IslandPressStyle())
        .help(microphones.isMuted ? "Unmute every microphone (\u{2303}\u{2325}M)" : "Mute every microphone (\u{2303}\u{2325}M)")
        .accessibilityLabel(microphones.isMuted ? "Unmute all microphones" : "Mute all microphones")
    }

    @ViewBuilder
    private func appIcon(for call: CallActivity) -> some View {
        if let icon = NSRunningApplication(processIdentifier: call.processIdentifier)?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: "phone.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(IslandTint.call)
                .frame(width: 44, height: 44)
                .background(IslandTint.call.opacity(0.18), in: Circle())
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: IslandSpace.m) {
            IslandHeader(title: "Calls", symbol: "phone.fill", tint: IslandTint.call,
                         subtitle: model.connectionStatus)
            Text("Zoom · FaceTime · Phone · WhatsApp · Discord · Teams · Meet")
                .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
                .help("Calls appear when the app exposes its microphone and end-call controls. Availability varies by app and language.")
            HStack(spacing: IslandSpace.s) {
                if !model.isDetectionEnabled {
                    Button("Resume detection", action: model.enableDetection)
                        .buttonStyle(IslandPillStyle(prominent: true))
                } else if model.needsAccessibilityPermission {
                    Button("Enable Accessibility", action: model.requestAccessibilityPermission)
                        .buttonStyle(IslandPillStyle(prominent: true))
                } else {
                    Button("Refresh", action: model.refresh).buttonStyle(IslandPillStyle())
                    Button("Pause detection", action: model.disconnect)
                        .buttonStyle(IslandPillStyle(compact: true))
                }
            }
            .disabled(model.isWorking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func control(_ title: String, icon: String, enabled: Bool, active: Bool? = nil, destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        let role: IslandControlButton.Role = destructive ? .destructive : active == true ? .active : .neutral
        return IslandControlButton(title: title, symbol: icon, role: role, diameter: 46, action: action)
            .disabled(!enabled || model.isWorking)
            .help(enabled ? title : "This app does not expose this control")
    }

    private func publishConfirmationState() {
        onConfirmationChange(confirmingLeave || confirmingScreenShare)
    }
}
