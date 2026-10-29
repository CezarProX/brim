import Darwin
import Foundation
import Testing

@testable import Brim

struct BluetoothBatteryTests {
  @Test func boundedProbeCapturesOutputAndTerminatesWorkerOnTimeout() async throws {
    let output = BluetoothBatteryProbe.boundedOutput(
      executable: "/usr/bin/printf", arguments: ["probe"], timeout: 2)
    #expect(output == Data("probe".utf8))
    let pidFile = URL(fileURLWithPath: "/tmp/brim-probe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: pidFile) }
    let started = ProcessInfo.processInfo.systemUptime
    let timedOut = BluetoothBatteryProbe.boundedOutput(
      executable: "/bin/sh",
      arguments: ["-c", "sleep 30 & echo $! > '\(pidFile.path)'; wait"], timeout: 0.3)
    #expect(timedOut == nil)
    #expect(ProcessInfo.processInfo.systemUptime - started < 3)
    let pidText = try String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)
    let child = try #require(Int32(pidText))
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while kill(child, 0) == 0 && ProcessInfo.processInfo.systemUptime < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(kill(child, 0) == -1 && errno == ESRCH)
  }

  @Test func connectedComponentsAreParsedAndDisconnectedCacheIsIgnored() throws {
    let payload: [String: Any] = [
      "SPBluetoothDataType": [
        [
          "device_connected": [
            [
              "Fixture earbuds": [
                "device_batteryLevelLeft": "85%",
                "device_batteryLevelRight": "82%", "device_batteryLevelCase": "91%",
              ]
            ]
          ],
          "device_not_connected": [["Old earbuds": ["device_batteryLevelLeft": "99%"]]],
        ]
      ]
    ]
    let devices = BluetoothBatteryProbe.decode(try JSONSerialization.data(withJSONObject: payload))
    #expect(devices.count == 3)
    #expect(Set(devices.map(\.percent)) == [85, 82, 91])
    #expect(!devices.contains { $0.name.contains("Old") })
  }

  @Test func unknownOutOfRangeAndOversizedDataAreOmitted() {
    #expect(BluetoothBatteryProbe.percent("Unknown") == nil)
    #expect(BluetoothBatteryProbe.percent("101%") == nil)
    #expect(BluetoothBatteryProbe.percent("-1%") == nil)
    #expect(BluetoothBatteryProbe.percent("0%") == 0)
    #expect(BluetoothBatteryProbe.decode(Data(repeating: 32, count: 1_048_577)).isEmpty)
  }
}
