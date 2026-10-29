import AppKit
import SwiftUI

/// First-run and "change city" for Weather, right inside the island: search a city or use this
/// Mac's location. Choosing either one turns Weather on; there is nothing to find in Settings.
@MainActor
struct WeatherSetupView: View {
  /// macOS has refused Location Services for Brim.
  var denied = false
  /// The place currently shown, so the card can say what "cancel" returns to.
  var current: String?
  let choose: (GeocodingResponse.Place) -> Void
  let useLocation: () -> Void
  var search: (String) async throws -> [GeocodingResponse.Place]
  var cancel: (() -> Void)?
  @State private var query: String
  @State private var results: [GeocodingResponse.Place]
  @State private var failed = false
  @State private var searching = false
  @FocusState private var focused: Bool

  init(
    denied: Bool = false, current: String? = nil, choose: @escaping (GeocodingResponse.Place) -> Void,
    useLocation: @escaping () -> Void, search: @escaping (String) async throws -> [GeocodingResponse.Place],
    cancel: (() -> Void)? = nil, query: String = "", results: [GeocodingResponse.Place] = [], failed: Bool = false
  ) {
    self.denied = denied
    self.current = current
    self.choose = choose
    self.useLocation = useLocation
    self.search = search
    self.cancel = cancel
    _query = State(initialValue: query)
    _results = State(initialValue: results)
    _failed = State(initialValue: failed)
  }

  private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    HStack(alignment: .top, spacing: IslandSpace.xl) {
      intro.frame(width: 190, alignment: .leading)
      VStack(alignment: .leading, spacing: 8) {
        field
        if !results.isEmpty { resultList } else if failed {
          note("Couldn’t reach the search service. Check your connection.")
        } else if trimmed.count >= 2 && !searching {
          note("No cities found")
        } else {
          locationButton
          if denied { deniedNote }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .padding(.top, 4)
    .task(id: trimmed) { await runSearch(trimmed) }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 34))
      Text("Weather for your city").font(IslandFont.title).foregroundStyle(IslandInk.primary)
      Text("Search for a city or use this Mac’s location. Only coordinates are sent to open-meteo.com. No account needed.")
        .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).fixedSize(horizontal: false, vertical: true)
      if let cancel {
        Button(action: cancel) {
          Text(current.map { L10n.tr("Back to %@", $0) } ?? L10n.tr("Cancel"))
        }
        .buttonStyle(IslandPillStyle()).padding(.top, 2)
      }
    }
  }

  private var field: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.tertiary)
      TextField(L10n.tr("Search for a city"), text: $query)
        .textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
        .onSubmit { if let first = results.first { choose(first) } }
      if searching { ProgressView().controlSize(.mini) }
      if !query.isEmpty {
        Button { query = ""; results = []; failed = false } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(IslandInk.tertiary).frame(width: 24, height: 24)
        }
        .buttonStyle(IslandPressStyle()).accessibilityLabel("Clear")
      }
    }
    .padding(.horizontal, 10).frame(height: 34)
    .background(IslandFill.raised, in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
    .onAppear { focused = true }
  }

  private var locationButton: some View {
    Button(action: useLocation) {
      Label("Use my location", systemImage: "location.fill").frame(maxWidth: .infinity)
    }
    .buttonStyle(IslandPillStyle(prominent: true, tint: .blue)).accessibilityHint("Uses an approximate position from this Mac")
  }

  private var deniedNote: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Location is off for Brim. Allow it in System Settings, or search for a city instead.")
        .font(.system(size: 12)).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
      Button("Open Location Settings") {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
          NSWorkspace.shared.open(url)
        }
      }
      .buttonStyle(IslandPillStyle(compact: true))
    }
  }

  private func note(_ text: LocalizedStringKey) -> some View {
    Text(text).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).padding(.top, 4)
  }

  private var resultList: some View {
    VStack(spacing: 2) {
      ForEach(results.prefix(4)) { place in
        Button { choose(place) } label: {
          HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill").foregroundStyle(IslandInk.secondary)
            Text(place.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
            Text(place.subtitle).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
          .glassCard(radius: IslandRadius.small)
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel("\(place.name), \(place.subtitle)")
      }
    }
  }

  /// Waits a beat after the last keystroke so typing doesn't fire a request per letter.
  private func runSearch(_ text: String) async {
    failed = false
    guard text.count >= 2 else {
      if !text.isEmpty { results = [] }
      searching = false
      return
    }
    searching = true
    defer { searching = false }
    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled else { return }
    do { results = try await search(text) } catch is CancellationError { return } catch {
      guard !Task.isCancelled else { return }
      results = []
      failed = true
    }
  }
}
