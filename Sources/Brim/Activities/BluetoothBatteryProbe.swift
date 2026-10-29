import Darwin
import Foundation

/// macOS exposes separate AirPods levels through System Information, not CoreBluetooth.
/// The "basic" detail level (as fast as "mini") includes the product ID that names the exact model.
/// Ignore cached disconnected records; run the fixed system tool off the main actor.
enum BluetoothBatteryProbe {
  static func decode(_ data: Data) -> [DeviceBattery] {
    guard data.count <= 1_048_576,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
    else { return [] }
    var result: [DeviceBattery] = []
    for controller in controllers {
      for entry in (controller["device_connected"] as? [[String: Any]] ?? []).prefix(12) {
        for (name, raw) in entry {
          guard let device = raw as? [String: Any] else { continue }
          let identifier = device["device_address"] as? String ?? name
          let displayName = String(name.prefix(70))
          let productID = hex(device["device_productID"])
          let model = AccessoryModel.identify(
            productID: productID, vendorID: hex(device["device_vendorID"]),
            name: name, type: device["device_minorType"] as? String)
          let components: [(String, String?, BatteryPart?)] = [
            ("device_batteryLevelLeft", "Left", .left),
            ("device_batteryLevelRight", "Right", .right),
            ("device_batteryLevelCase", "Case", .case),
            ("device_batteryLevelMain", nil, nil),
          ]
          for (key, label, part) in components {
            guard let value = device[key] as? String, let level = percent(value) else { continue }
            result.append(
              DeviceBattery(
                id: "bluetooth:\(identifier):\(key)",
                name: label.map { "\(displayName) · \($0)" } ?? displayName, symbol: model.glyph(for: part),
                percent: level, charging: nil, accessoryID: "bluetooth:\(identifier)",
                accessoryName: displayName, part: part, model: model, productID: productID))
          }
        }
      }
    }
    var ids = Set<String>()
    return Array(result.filter { ids.insert($0.id).inserted }.prefix(12))
  }

  /// `system_profiler` reports IDs as hex text, e.g. "0x2024".
  static func hex(_ value: Any?) -> Int? {
    guard let text = value as? String, text.lowercased().hasPrefix("0x") else { return nil }
    return Int(text.dropFirst(2), radix: 16)
  }

  static func percent(_ value: String) -> Int? {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.hasSuffix("%"), let number = Int(raw.dropLast()), (0...100).contains(number) else {
      return nil
    }
    return number
  }

  static func read() -> [DeviceBattery] {
    guard
      let data = boundedOutput(
        executable: "/usr/sbin/system_profiler",
        arguments: ["SPBluetoothDataType", "-json", "-detailLevel", "basic", "-timeout", "4"],
        timeout: 5
      )
    else { return [] }
    return decode(data)
  }

  /// Own the entire process group, including system_profiler's worker subprocess.
  static func boundedOutput(executable: String, arguments: [String], timeout: TimeInterval) -> Data?
  {
    var descriptors: [Int32] = [-1, -1]
    guard pipe(&descriptors) == 0 else { return nil }
    defer { close(descriptors[0]) }
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    guard posix_spawn_file_actions_init(&actions) == 0 else {
      close(descriptors[1])
      return nil
    }
    defer { posix_spawn_file_actions_destroy(&actions) }
    guard posix_spawnattr_init(&attributes) == 0 else {
      close(descriptors[1])
      return nil
    }
    defer { posix_spawnattr_destroy(&attributes) }
    guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
      posix_spawnattr_setpgroup(&attributes, 0) == 0,
      posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO) == 0,
      posix_spawn_file_actions_addclose(&actions, descriptors[0]) == 0,
      posix_spawn_file_actions_addclose(&actions, descriptors[1]) == 0,
      posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
      posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0
    else {
      close(descriptors[1])
      return nil
    }
    let strings = ([executable] + arguments).map { strdup($0) }
    let environmentStrings: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C"]
    let environment = environmentStrings.map { strdup($0) }
    defer {
      strings.forEach { free($0) }
      environment.forEach { free($0) }
    }
    var argv = strings + [nil]
    var envp = environment + [nil]
    var pid: pid_t = 0
    let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, &envp)
    close(descriptors[1])
    guard status == 0 else { return nil }
    defer {
      // Keep the leader unreaped until group cleanup so its PID cannot be reused.
      kill(-pid, SIGKILL)
      var exitStatus: Int32 = 0
      while waitpid(pid, &exitStatus, 0) == -1 && errno == EINTR {}
    }
    let descriptor = descriptors[0]
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while ProcessInfo.processInfo.systemUptime < deadline {
      var item = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
      guard poll(&item, 1, 100) > 0 else { continue }
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { return data }
      guard count > 0, data.count + count <= 1_048_576 else { return nil }
      data.append(contentsOf: buffer.prefix(count))
    }
    return nil
  }
}
