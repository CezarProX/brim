import SwiftUI

struct LockTimerCard: View {
    let info: LockTimerInfo
    let look: LockScreenLook
    let actions: LockCardActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = info.remaining(at: context.date)
            let fraction = info.duration > 0 ? remaining / info.duration : 0
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(info.tint.opacity(0.22), lineWidth: 6)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(info.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: info.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(info.tint)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.isPaused ? "\(info.title) · Paused" : info.title)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(info.tint).lineLimit(1)
                    Text(LockTimeFormat.clock(remaining))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer(minLength: 0)
                if info.canControl {
                    LockRoundButton(symbol: info.isPaused ? "play.fill" : "pause.fill",
                                    label: info.isPaused ? "Resume timer" : "Pause timer",
                                    size: 44, tint: info.tint, action: actions.toggleTimer)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(width: LockScreenLayout.cardWidth, height: LockCardKind.timer.height)
        .background { LockIslandSlab(radius: 28) }
    }
}

/// Keep Awake, shown as "High Alert".
struct LockAwakeCard: View {
    let info: LockAwakeInfo
    let look: LockScreenLook
    let actions: LockCardActions
    private let tint = Color.yellow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 44, height: 44).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("High Alert").font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
            Button(action: actions.stopAwake) {
                Text("Stop").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: Capsule())
            }
            .buttonStyle(IslandPressStyle())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(width: LockScreenLayout.cardWidth, height: LockCardKind.awake.height)
        .background { LockIslandSlab(radius: 28) }
    }

    private var subtitle: String {
        info.until.map { "Mac stays awake until " + $0.formatted(date: .omitted, time: .shortened) }
            ?? "Mac stays awake until you turn it off"
    }
}

/// The glanceable row under the lock-screen clock.
struct LockStatusRowView: View {
    let items: [LockStatusItem]
    let look: LockScreenLook

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(item.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text(item.detail).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background { LockIslandSlab(radius: 18) }
            }
        }
        .frame(width: LockScreenLayout.cardWidth, height: LockScreenLayout.statusRowHeight)
    }
}

/// The stack as one view: top to bottom in layout order.
struct LockCardsStack: View {
    let content: LockCardsContent
    let kinds: [LockCardKind]
    let look: LockScreenLook
    let actions: LockCardActions

    var body: some View {
        VStack(spacing: LockScreenLayout.spacing) {
            ForEach(kinds, id: \.self) { kind in
                switch kind {
                case .nowPlaying:
                    if let media = content.media { LockMediaCard(info: media, look: look, actions: actions) }
                case .awake:
                    if let awake = content.awake { LockAwakeCard(info: awake, look: look, actions: actions) }
                case .timer:
                    if let timer = content.timer { LockTimerCard(info: timer, look: look, actions: actions) }
                }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.18), value: kinds)
    }
}
