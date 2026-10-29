import AVFoundation
import AppKit
import Darwin

/// A quick note kept in the notch.
struct IslandNote: Codable, Identifiable, Equatable {
  let id: UUID
  var text: String
  var edited: Date
  var pinned = false
  /// Id of the mirrored note in Apple Notes, once synced.
  var appleID: String? = nil

  init(id: UUID, text: String, edited: Date, pinned: Bool = false, appleID: String? = nil) {
    self.id = id
    self.text = text
    self.edited = edited
    self.pinned = pinned
    self.appleID = appleID
  }

  // Notes saved before pinning existed have neither field.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    text = try c.decode(String.self, forKey: .text)
    edited = try c.decode(Date.self, forKey: .edited)
    pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    appleID = try c.decodeIfPresent(String.self, forKey: .appleID)
  }

  var title: String {
    let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    let clean = first.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
    return clean.isEmpty ? "New note" : String(clean.prefix(60))
  }
}

/// Local notes stored as one JSON file under Application Support.
@MainActor
final class NotesModel: ObservableObject {
  static let shared = NotesModel()
  static let maximumNotes = 50
  static let maximumLength = 20_000
  @Published private(set) var notes: [IslandNote] = []
  @Published var selectedID: UUID?
  @Published private(set) var errorMessage: String?
  private let url: URL

  init(directory: URL? = nil) {
    let folder =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim", isDirectory: true)
    url = folder.appendingPathComponent("notes.json")
    if let data = try? Data(contentsOf: url), data.count < 5_000_000,
      let decoded = try? JSONDecoder().decode([IslandNote].self, from: data)
    {
      notes = Array(decoded.prefix(Self.maximumNotes))
    }
    selectedID = notes.first?.id
  }

  var selected: IslandNote? { notes.first { $0.id == selectedID } }

  @discardableResult
  func create(now: Date = .now) -> IslandNote {
    let note = IslandNote(id: UUID(), text: "", edited: now)
    save(Self.ordered(Array(([note] + notes).prefix(Self.maximumNotes))))
    selectedID = note.id
    return note
  }

  func update(_ id: UUID, text: String, now: Date = .now) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    var next = notes
    var note = next[index]
    note.text = String(text.prefix(Self.maximumLength))
    note.edited = now
    next[index] = note
    // The note being edited floats to the top of its group, like the Notes app.
    next.remove(at: index)
    save(Self.ordered([note] + next))
  }

  func togglePin(_ id: UUID) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    var next = notes
    next[index].pinned.toggle()
    save(Self.ordered(next))
  }

  func setAppleID(_ appleID: String, for id: UUID) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    var next = notes
    next[index].appleID = appleID
    save(next)
  }

  /// Imports notes from elsewhere (Apple Notes), skipping ones already mirrored.
  func merge(_ incoming: [IslandNote]) {
    save(Self.ordered(Array((incoming + notes).prefix(Self.maximumNotes))))
  }

  /// Pinned notes first; the rest keep their order.
  nonisolated static func ordered(_ notes: [IslandNote]) -> [IslandNote] {
    notes.filter(\.pinned) + notes.filter { !$0.pinned }
  }

  /// Case-insensitive search across the whole note text.
  nonisolated static func filter(_ notes: [IslandNote], query: String) -> [IslandNote] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return notes }
    return notes.filter { $0.text.localizedCaseInsensitiveContains(needle) }
  }

  func delete(_ id: UUID) {
    save(notes.filter { $0.id != id })
    if selectedID == id { selectedID = notes.first?.id }
  }

  private func save(_ next: [IslandNote]) {
    notes = next
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(next).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      errorMessage = nil
    } catch { errorMessage = "Couldn’t save notes. \(error.localizedDescription)" }
  }
}

/// CPU, memory and disk figures from public Mach and Foundation APIs.
enum SystemStatsMath {
  struct CPUTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
  }

  /// Fraction of time busy between two samples, 0...1.
  static func usage(from previous: CPUTicks, to current: CPUTicks) -> Double {
    let total = current.total &- previous.total
    guard total > 0, current.total >= previous.total else { return 0 }
    return min(1, max(0, Double(current.busy &- previous.busy) / Double(total)))
  }
}

@MainActor
final class SystemStatsModel: ObservableObject {
  static let shared = SystemStatsModel()
  @Published private(set) var cpu: Double = 0
  @Published private(set) var memoryUsed: UInt64 = 0
  @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
  @Published private(set) var diskFree: Int64 = 0
  @Published private(set) var diskTotal: Int64 = 0
  @Published private(set) var cpuHistory: [Double] = []
  /// Recent samples for the stats widget's mini graphs.
  @Published private(set) var history = StatsHistory()
  /// CPU usage needs two samples; until then `cpu` is not a real reading.
  @Published private(set) var hasCPUReading = false
  @Published private(set) var gpu: Double?
  @Published private(set) var networkDown: Double = 0
  @Published private(set) var networkUp: Double = 0
  @Published private(set) var batteryPercent: Int?
  @Published private(set) var batteryCharging = false
  @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
  private var previous: SystemStatsMath.CPUTicks?
  private var previousNetwork: (counters: NetworkMath.Counters, at: Date)?
  private var timer: Timer?
  private var viewers = 0

  /// Sampling runs only while a stats view is on screen.
  func attach() {
    viewers += 1
    guard timer == nil else { return }
    sample()
    // A quick second sample so the page shows real CPU usage almost immediately.
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      self?.sample()
    }
    startTimer()
  }

  /// Re-reads the interval setting; call after it changes.
  func intervalChanged() {
    guard timer != nil else { return }
    startTimer()
  }

  private func startTimer() {
    timer?.invalidate()
    let seconds = TimeInterval(AppSettings.shared.statsSampleSeconds)
    timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.sample() }
    }
  }

  func detach() {
    viewers = max(0, viewers - 1)
    guard viewers == 0 else { return }
    timer?.invalidate()
    timer = nil
  }

  private func sample() {
    if let ticks = Self.cpuTicks() {
      if let previous {
        cpu = SystemStatsMath.usage(from: previous, to: ticks)
        hasCPUReading = true
        cpuHistory = Array((cpuHistory + [cpu]).suffix(40))
      }
      previous = ticks
    }
    memoryUsed = Self.memoryUsed() ?? memoryUsed
    sampleExtras()
    history.record(
      cpu: hasCPUReading ? cpu : nil, memory: Double(memoryUsed) / Double(max(1, memoryTotal)),
      gpu: gpu, down: networkDown, up: networkUp)
    if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
    ]) {
      diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
      diskTotal = Int64(values.volumeTotalCapacity ?? 0)
    }
  }

  private func sampleExtras() {
    gpu = SystemStatsReaders.gpuUsage()
    thermalState = ProcessInfo.processInfo.thermalState
    let battery = SystemStatsReaders.battery()
    batteryPercent = battery?.percent
    batteryCharging = battery?.charging ?? false
    guard let counters = SystemStatsReaders.networkCounters() else { return }
    let now = Date()
    if let last = previousNetwork {
      let rates = NetworkMath.rates(from: last.counters, to: counters, seconds: now.timeIntervalSince(last.at))
      networkDown = rates.down
      networkUp = rates.up
    }
    previousNetwork = (counters, now)
  }

  nonisolated static func cpuTicks() -> SystemStatsMath.CPUTicks? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return SystemStatsMath.CPUTicks(
      user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
      idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
  }

  nonisolated static func memoryUsed() -> UInt64? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let page = UInt64(vm_kernel_page_size)
    // Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    let anonymous = UInt64(stats.internal_page_count)
    let purgeable = UInt64(stats.purgeable_count)
    let app = anonymous > purgeable ? anonymous - purgeable : 0
    return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
  }
}
