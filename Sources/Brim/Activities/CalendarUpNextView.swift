import AppKit
import EventKit
import SwiftUI

/// The Calendar tool: the iOS "Up Next" widget when connected, a proper permission screen when not.
struct CalendarActivityView: View {
  @ObservedObject var model: CalendarActivityModel

  var body: some View {
    if model.enabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess {
      TimelineView(.periodic(from: .now, by: 30)) { context in
        CalendarUpNextPanel(model: model, now: context.date)
      }
    } else {
      CalendarAccessPrompt(model: model)
    }
  }
}

private let calendarRed = Color(nsColor: .systemRed)

/// Today's date the way Calendar draws it: red weekday over a large day number.
private struct CalendarDateBlock: View {
  let now: Date
  let summary: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(now, format: .dateTime.weekday(.wide))
        .font(.system(size: 12, weight: .semibold)).textCase(.uppercase)
        .foregroundStyle(calendarRed)
      Text(now, format: .dateTime.day())
        .font(.system(size: 46, weight: .regular)).monospacedDigit()
        .padding(.top, -2)
      Text(summary).font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
    }
    .frame(width: 104, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

struct CalendarUpNextPanel: View {
  @ObservedObject var model: CalendarActivityModel
  let now: Date

  var body: some View {
    let upNext = CalendarUpNext.make(model.agenda.flatMap(\.items), now: now)
    HStack(alignment: .top, spacing: IslandSpace.xl) {
      CalendarDateBlock(now: now, summary: summary(upNext))
      VStack(alignment: .leading, spacing: IslandSpace.m) {
        HStack(spacing: IslandSpace.s) {
          Text(headingText(upNext.heading))
            .font(IslandFont.caption).textCase(.uppercase).foregroundStyle(IslandInk.tertiary)
          Spacer(minLength: 0)
          CalendarMoreMenu(model: model)
        }
        if let allDay = upNext.allDay.first {
          HStack(spacing: 6) {
            Circle().fill(allDay.color).frame(width: 6, height: 6)
            Text(allDay.title).lineLimit(1)
            if upNext.allDay.count > 1 {
              Text("+\(upNext.allDay.count - 1)").foregroundStyle(IslandInk.tertiary)
            }
          }
          .font(IslandFont.label).foregroundStyle(IslandInk.secondary)
        }
        if upNext.events.isEmpty {
          Text("Nothing scheduled").font(IslandFont.title).foregroundStyle(IslandInk.secondary)
          Text("Your next two weeks are clear.").font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
        }
        ForEach(Array(upNext.events.enumerated()), id: \.element.id) { index, item in
          UpNextRow(item: item, now: now, emphasised: index == 0 && upNext.heading == nil)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .animation(.spring(duration: 0.4, bounce: 0.1), value: upNext)
  }

  private func headingText(_ heading: CalendarUpNext.Heading?) -> String {
    switch heading {
    case nil: "Up Next"
    case .tomorrow: "Tomorrow"
    case .day(let day): day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
  }

  private func summary(_ upNext: CalendarUpNext) -> String {
    switch upNext.remainingToday {
    case 0: "No more events today"
    case 1: "1 event left"
    default: "\(upNext.remainingToday) events left"
    }
  }
}

/// One event: calendar color bar, title, time range; the next one also gets a countdown and Join.
private struct UpNextRow: View {
  let item: CalendarAgendaItem
  let now: Date
  let emphasised: Bool

  var body: some View {
    let inProgress = item.start <= now
    HStack(alignment: .center, spacing: 10) {
      Capsule().fill(item.color).frame(width: 4, height: emphasised ? 38 : 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).font(emphasised ? IslandFont.title : IslandFont.headline).lineLimit(1)
        Text(timeRange).font(IslandFont.label).foregroundStyle(IslandInk.secondary).monospacedDigit()
        if emphasised && inProgress {
          GeometryReader { proxy in
            Capsule().fill(IslandFill.raised)
              .overlay(alignment: .leading) {
                Capsule().fill(item.color)
                  .frame(width: proxy.size.width * CalendarUpNext.progress(of: item, now: now))
              }
          }
          .frame(width: 120, height: 3).padding(.top, 3)
        }
      }
      Spacer(minLength: IslandSpace.s)
      if emphasised {
        Text(CalendarUpNext.countdown(to: item, now: now))
          .font(IslandFont.label.weight(.semibold)).monospacedDigit()
          .foregroundStyle(item.start.timeIntervalSince(now) <= 600 ? calendarRed : IslandInk.secondary)
          .contentTransition(.numericText())
        if let url = item.joinURL {
          Button {
            NSWorkspace.shared.open(url)
          } label: {
            Label("Join", systemImage: "video.fill")
          }
          .buttonStyle(IslandPillStyle(prominent: true, tint: .green, compact: true))
          .help("Join \(url.host ?? "the call")")
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var timeRange: String {
    guard let end = item.end else { return item.start.formatted(date: .omitted, time: .shortened) }
    return "\(item.start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
  }
}

private struct CalendarMoreMenu: View {
  @ObservedObject var model: CalendarActivityModel

  var body: some View {
    Menu {
      Button("Open Calendar") {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
          NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
      }
      Divider()
      Button("Disconnect Calendar", role: .destructive, action: model.disconnect)
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 11, weight: .bold)).foregroundStyle(IslandInk.secondary)
        .frame(width: 22, height: 22).background(IslandFill.subtle, in: Circle())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Calendar options")
  }
}

/// A Calendar-style date tile beside one sentence and one action.
private struct CalendarAccessPrompt: View {
  @ObservedObject var model: CalendarActivityModel
  @State private var attempted = false

  private var denied: Bool {
    [.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .event))
  }

  var body: some View {
    HStack(alignment: .center, spacing: IslandSpace.l) {
      TimelineView(.everyMinute) { context in
        VStack(spacing: 0) {
          Text(context.date, format: .dateTime.weekday(.abbreviated))
            .font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
            .foregroundStyle(calendarRed).padding(.top, 6)
          Text(context.date, format: .dateTime.day())
            .font(.system(size: 30, weight: .light)).foregroundStyle(.black)
            .padding(.top, -3)
          Spacer(minLength: 0)
        }
        .frame(width: 58, height: 58)
        .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Connect your calendar").font(IslandFont.title)
        Text(denied
             ? "Calendar access is off for Brim. Turn it on in System Settings > Privacy & Security > Calendars."
             : "See today’s events, join video calls in one tap and add events by typing. Your calendar stays on this Mac.")
          .font(IslandFont.body).foregroundStyle(IslandInk.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Group {
          if denied {
            Button("Open Calendar Privacy Settings") {
              if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
              }
            }
          } else {
            Button("Connect Calendar") {
              attempted = true
              Task { await model.connect() }
            }
            .disabled(model.isWorking)
          }
        }
        .buttonStyle(IslandPillStyle(prominent: true))
        .padding(.top, 6)
        // Without this a refused or failed request looks like a button that does nothing.
        if attempted && !model.isWorking {
          Text(model.status).font(IslandFont.body).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
        }
      }
      Spacer(minLength: 0)
    }
  }
}
