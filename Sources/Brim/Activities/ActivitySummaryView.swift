import SwiftUI

@MainActor
struct ActivitySummaryView: View {
  @ObservedObject var center: ActivityCenter
  let onSelect: (IslandActivity) -> Void

  var body: some View {
    HStack(spacing: IslandSpace.s) {
      batterySummary
      meetingSummary
    }
    .frame(maxWidth: .infinity, minHeight: 36)
  }

  @ViewBuilder
  private var batterySummary: some View {
    if let device = center.batteries.devices.first {
      summaryChip(activity: .devices) {
        Image(systemName: device.charging == true ? "bolt.fill" : device.symbol)
          .foregroundStyle(device.charging == true || device.percent > 20 ? .green : .red)
        Text("\(device.percent)%").monospacedDigit().contentTransition(.numericText())
      }
    } else {
      summaryChip(activity: .devices) {
        Image(systemName: "battery.100percent")
        Text("Batteries")
      }
    }
  }

  @ViewBuilder
  private var meetingSummary: some View {
    if let meeting = center.calendar.meeting {
      HStack(spacing: 6) {
        summaryChip(activity: .calendar) {
          Image(systemName: "calendar").foregroundStyle(IslandTint.color(for: .calendar))
          Text(meeting.title).lineLimit(1)
          Text(meeting.startsAt, style: .time).monospacedDigit().foregroundStyle(IslandInk.tertiary)
        }
        if meeting.joinURL != nil {
          Button("Join") { center.calendar.join(meeting.id) }
            .buttonStyle(IslandPillStyle(prominent: true, tint: .green, compact: true))
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    } else {
      Spacer(minLength: 0)
      summaryChip(activity: .calendar) {
        Image(systemName: "calendar")
        Text("Calendar")
      }
    }
  }

  private func summaryChip<Content: View>(
    activity: IslandActivity, @ViewBuilder content: () -> Content
  ) -> some View {
    Button { onSelect(activity) } label: {
      HStack(spacing: 5) { content() }
    }
    .buttonStyle(IslandPillStyle(compact: true))
  }
}
