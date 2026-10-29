import AppKit
import Foundation

/// State behind the Transform panel: the files, the chosen operation and its options,
/// and the progress of a run.
@MainActor
final class TransformPanelModel: ObservableObject {
  struct Row: Identifiable, Equatable {
    let id: Int
    let sources: [URL]
    var state: TransformUnitState = .waiting

    var title: String {
      sources.count == 1 ? sources[0].lastPathComponent : "\(sources.count) files"
    }
  }

  enum Phase { case configure, running, finished }

  @Published private(set) var files: [URL]
  @Published private(set) var operation: TransformOperation
  @Published var group: TransformGroup
  @Published var options: TransformOptions
  @Published private(set) var rows: [Row] = []
  @Published private(set) var phase: Phase = .configure
  @Published private(set) var userPresets: [TransformPreset]
  private var task: Task<Void, Never>?
  private let settings: AppSettings

  init(files: [URL], settings: AppSettings = .shared) {
    self.files = files
    self.settings = settings
    let first = TransformOperation.suggested(for: files) ?? .zip
    operation = first
    group = first.group
    options = settings.transformDefaultOptions
    userPresets = settings.transformUserPresets
  }

  // MARK: Choices

  var available: [TransformOperation] { TransformOperation.available(for: files) }

  /// Groups that have at least one operation for these files, in display order.
  var groups: [TransformGroup] {
    TransformGroup.allCases.filter { group in available.contains { $0.group == group } }
  }

  var operationsInGroup: [TransformOperation] { available.filter { $0.group == group } }

  var presets: [TransformPreset] {
    TransformPreset.applicable(TransformPreset.builtIn + userPresets, to: files)
  }

  var kinds: Set<TransformFileKind> { Set(files.map(TransformFileKind.init(url:))) }

  func select(_ next: TransformOperation) {
    guard available.contains(next) else { return }
    operation = next
    group = next.group
  }

  func select(group next: TransformGroup) {
    group = next
    if let first = operationsInGroup.first, operation.group != next { operation = first }
  }

  func apply(_ preset: TransformPreset) {
    guard available.contains(preset.operation) else { return }
    options = preset.options
    select(preset.operation)
  }

  func remove(_ file: URL) {
    guard phase == .configure, files.count > 1 else { return }
    files.removeAll { $0 == file }
    if !available.contains(operation), let next = TransformOperation.suggested(for: files) { select(next) }
  }

  /// Adds files from the panel's "+ Add" tile; duplicates are skipped.
  func add(_ urls: [URL]) {
    guard phase == .configure else { return }
    files += urls.filter { !files.contains($0) }
    if !available.contains(operation), let next = TransformOperation.suggested(for: files) { select(next) }
  }

  /// Where results go; the panel's "Save to" menu writes the user's setting.
  func setDestination(_ destination: TransformDestination) {
    objectWillChange.send()
    settings.transformDestination = destination
  }

  func savePreset(named name: String) {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    let preset = TransformPreset(
      id: UUID().uuidString, name: clean, symbol: operation.symbol, operation: operation, options: options)
    userPresets.append(preset)
    settings.transformUserPresets = userPresets
  }

  func deletePreset(_ preset: TransformPreset) {
    userPresets.removeAll { $0.id == preset.id }
    settings.transformUserPresets = userPresets
  }

  // MARK: Running

  var policy: TransformOutputPolicy { settings.transformOutputPolicy }
  var canRun: Bool { phase == .configure && available.contains(operation) && !files.isEmpty }

  func run() {
    guard canRun else { return }
    let units = TransformEngine.units(for: files, operation: operation)
    rows = units.enumerated().map { Row(id: $0.offset, sources: $0.element) }
    phase = .running
    let operation = operation, options = options, policy = policy
    let model = self
    task = Task.detached(priority: .userInitiated) {
      await TransformEngine.run(units: units, operation: operation, options: options, policy: policy) { index, state in
        Task { @MainActor in model.update(index, state) }
      }
      await MainActor.run { model.finish() }
    }
  }

  func cancel() {
    task?.cancel()
  }

  /// Back to choosing an operation for the same files.
  func again() {
    guard phase == .finished else { return }
    rows = []
    phase = .configure
  }

  func update(_ index: Int, _ state: TransformUnitState) {
    guard rows.indices.contains(index) else { return }
    // A late progress tick must not undo a finished row.
    if case .running = state, rows[index].state != .waiting, !isRunning(rows[index].state) { return }
    rows[index].state = state
  }

  private func isRunning(_ state: TransformUnitState) -> Bool {
    if case .running = state { return true }
    return false
  }

  private func finish() {
    phase = .finished
    if settings.transformKeepResultsInTray, !results.isEmpty { FileTrayStore.shared.add(results) }
    if policy.revealInFinder, !results.isEmpty { reveal() }
  }

  // MARK: Results

  var results: [URL] {
    rows.flatMap { row -> [URL] in
      if case .done(let outcome) = row.state { return outcome.outputs }
      return []
    }
  }

  var failureCount: Int {
    rows.filter { if case .failed = $0.state { true } else { false } }.count
  }

  /// One line over all finished rows: "4.2 MB → 680 KB, −84%".
  var totalSummary: String? {
    var before: Int64 = 0, after: Int64 = 0
    var any = false
    for row in rows {
      guard case .done(let outcome) = row.state else { continue }
      before += outcome.bytesBefore
      after += outcome.bytesAfter
      any = true
    }
    return any ? TransformSizeSummary.text(before: before, after: after) : nil
  }

  var overallProgress: Double {
    guard !rows.isEmpty else { return 0 }
    let sum = rows.reduce(0.0) { total, row in
      switch row.state {
      case .waiting: total
      case .running(let value): total + value
      default: total + 1
      }
    }
    return sum / Double(rows.count)
  }

  func reveal() {
    NSWorkspace.shared.activateFileViewerSelecting(results)
  }

  /// Adds the results to the Tray and says so, since the panel closes right after.
  func keepInTray() {
    let added = FileTrayStore.shared.add(results)
    IslandFlashCenter.shared.show(
      added == 1 ? "Kept 1 file" : "Kept \(added) files", symbol: "tray.and.arrow.down.fill", tint: .blue)
  }

  /// Test and preview hook: puts the model in a given phase with given rows.
  func setForPreview(phase: Phase, rows: [Row]) {
    self.phase = phase
    self.rows = rows
  }
}
