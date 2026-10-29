import SwiftUI

/// Stay Awake options beyond the basic toggle.
struct StayAwakeSettingsSection: View {
  @State private var display = AppSettings.shared.stayAwakeKeepDisplayOn
  @State private var adapter = AppSettings.shared.stayAwakeOnPowerAdapter
  @State private var scheduled = AppSettings.shared.stayAwakeScheduleEnabled
  @State private var start = Self.date(AppSettings.shared.stayAwakeScheduleStart)
  @State private var end = Self.date(AppSettings.shared.stayAwakeScheduleEnd)
  @State private var days = AppSettings.shared.stayAwakeScheduleDays
  @State private var lid = AppSettings.shared.stayAwakeLidClosedOnPower
  @ObservedObject private var controller = StayAwakeController.shared

  var body: some View {
    SettingsSection("Stay Awake") {
      Toggle("Keep the display on too (off lets the screen sleep)", isOn: $display)
        .onChange(of: display) { _, value in save { $0.stayAwakeKeepDisplayOn = value } }
      Toggle("Stay awake automatically while on the power adapter", isOn: $adapter)
        .onChange(of: adapter) { _, value in save { $0.stayAwakeOnPowerAdapter = value } }
      Toggle("Stay awake on a schedule", isOn: $scheduled)
        .onChange(of: scheduled) { _, value in save { $0.stayAwakeScheduleEnabled = value } }
      if scheduled { schedule }
      Toggle("Keep running with the lid closed while on power", isOn: $lid)
        .onChange(of: lid) { _, value in save { $0.stayAwakeLidClosedOnPower = value } }
      if lid {
        Text("macOS asks for your administrator password when this turns on and off. Brim switches it off again when Stay Awake ends or the app quits; if the app crashes while it is on, run “sudo pmset -a disablesleep 0” in Terminal. Don’t put a running MacBook in a bag.")
          .font(.caption).foregroundStyle(.orange)
      }
      if let error = controller.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
    }
  }

  private var schedule: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
          .onChange(of: start) { _, value in save { $0.stayAwakeScheduleStart = Self.minutes(value) } }
        DatePicker("to", selection: $end, displayedComponents: .hourAndMinute)
          .onChange(of: end) { _, value in save { $0.stayAwakeScheduleEnd = Self.minutes(value) } }
      }
      HStack(spacing: 4) {
        ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, name in
          let day = index + 1
          Button(String(name.prefix(2))) {
            if days.contains(day) { days.remove(day) } else { days.insert(day) }
            save { $0.stayAwakeScheduleDays = days }
          }
          .buttonStyle(.bordered).tint(days.contains(day) ? .accentColor : .gray).controlSize(.small)
        }
      }
    }
  }

  private func save(_ change: (AppSettings) -> Void) {
    change(AppSettings.shared)
    StayAwakeController.shared.reconcile()
  }

  private static func date(_ minutes: Int) -> Date {
    Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
  }

  private static func minutes(_ date: Date) -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }
}
