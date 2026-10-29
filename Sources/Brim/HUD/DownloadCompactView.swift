import SwiftUI

/// Compact live activity for a running download: a progress ring (spinning when the browser does not
/// expose the total) on the leading wing and the time left ("5 sec") on the trailing wing.
struct DownloadRingView: View {
    let fraction: Double?
    var size: CGFloat = 20
    var tint: Color = Color(red: 0.25, green: 0.55, blue: 1)
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2.4)
            Circle().trim(from: 0, to: fraction ?? 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && spin ? 360 : 0)))
            Image(systemName: "arrow.down").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.4, bounce: 0), value: fraction)
        .onAppear {
            guard fraction == nil, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityLabel(fraction.map { "Download \(Int($0 * 100)) percent" } ?? "Downloading")
    }
}

struct DownloadCompactLeading: View {
    let snapshot: DownloadSnapshot
    var body: some View { DownloadRingView(fraction: snapshot.fraction) }
}

struct DownloadCompactTrailing: View {
    let snapshot: DownloadSnapshot
    var body: some View {
        Text(snapshot.trailingText)
            .font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(IslandInk.primary)
            .lineLimit(1).contentTransition(.numericText(countsDown: true))
            .animation(.spring(duration: 0.3, bounce: 0), value: snapshot.trailingText)
    }
}

/// Both wings in one row, for hosts that draw the wings themselves (tests, previews).
struct DownloadCompactView: View {
    @ObservedObject var model: DownloadProgressModel
    var notchWidth: CGFloat = 190
    var body: some View {
        if let snapshot = model.active {
            HStack(spacing: 0) {
                DownloadCompactLeading(snapshot: snapshot).frame(width: HUDMetrics.wing)
                Spacer(minLength: notchWidth)
                DownloadCompactTrailing(snapshot: snapshot).frame(width: HUDMetrics.wing)
            }
        }
    }
}

/// The open island's view of a running download: a large ring, the file name and what is left.
struct DownloadActivityCard: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        HStack(spacing: IslandSpace.l) {
            DownloadRingView(fraction: snapshot.fraction, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.name).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
                Text(detail).font(IslandFont.caption).foregroundStyle(IslandInk.secondary).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            Spacer(minLength: 0)
        }
        .padding(IslandSpace.l)
        .glassCard(radius: IslandRadius.medium)
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: snapshot.bytes, countStyle: .file)
        let more = snapshot.count > 1 ? " · \(snapshot.count) downloads" : ""
        return [size, snapshot.timeLeftText.map { "\($0) left" }].compactMap { $0 }.joined(separator: " · ") + more
    }
}
