import ServiceManagement
import SwiftUI

/// Where the tour is. The window owns one so the arrow keys and the buttons share it.
@MainActor
final class OnboardingFlow: ObservableObject {
  @Published private(set) var page: OnboardingPage
  /// True while moving toward later pages; the content slides the matching way.
  @Published private(set) var forward = true
  /// The pages of this tour, in order (the reply page is optional).
  let pages: [OnboardingPage]

  init(page: OnboardingPage = .welcome, pages: [OnboardingPage]? = nil) {
    let list = pages ?? OnboardingPage.tour(offeringReplies: page == .replies || !ReplyLinkOffer.pending().isEmpty)
    self.pages = list.contains(page) ? list : OnboardingPage.allCases
    self.page = page
  }

  var index: Int { pages.firstIndex(of: page) ?? 0 }
  var isLast: Bool { page == pages.last }

  func go(to index: Int) {
    guard pages.indices.contains(index), pages[index] != page else { return }
    forward = index > self.index
    page = pages[index]
  }

  func step(_ delta: Int) { go(to: index + delta) }
}

/// The tour window's content: night-sky art, the page's live demo, dots, copy and Continue.
struct OnboardingView: View {
  @ObservedObject var flow: OnboardingFlow
  @StateObject private var fixtures: OnboardingFixtures
  @StateObject private var permissions = PermissionsModel()
  @StateObject private var replies: TourReplyModel
  @StateObject private var island = TourIslandModels(clipboard: OnboardingSamples.clipboardEntries())
  var hudStep: Int?
  var onFinish: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let size = OnboardingMetrics.size

  init(flow: OnboardingFlow, sample: NowPlayingModel? = nil, hudStep: Int? = nil, replyPhase: LinkPhase? = nil,
       onFinish: @escaping () -> Void = {}) {
    self.flow = flow
    _replies = StateObject(wrappedValue: TourReplyModel(previewPhase: replyPhase))
    _fixtures = StateObject(wrappedValue: OnboardingFixtures(sample: sample))
    self.hudStep = hudStep
    self.onFinish = onFinish
  }

  init(page: OnboardingPage = .welcome, sample: NowPlayingModel? = nil, hudStep: Int? = nil, replyPhase: LinkPhase? = nil,
       onFinish: @escaping () -> Void = {}) {
    self.init(flow: OnboardingFlow(page: page), sample: sample, hudStep: hudStep, replyPhase: replyPhase, onFinish: onFinish)
  }

  private var page: OnboardingPage { flow.page }
  private var progress: Double { Double(flow.index) / Double(max(1, flow.pages.count - 1)) }
  private var rows: Bool { page.optionRowCount > 0 }

  private var slide: AnyTransition {
    let edge: Edge = flow.forward ? .trailing : .leading
    return .asymmetric(
      insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.96)))
  }

  var body: some View {
    ZStack(alignment: .top) {
      OnboardingScene(progress: progress)
      shade
      band
      realIsland
      hero
      copy
      options
      TourContinueButton(title: flow.isLast ? OnboardingPage.finish.buttonTitle : page.buttonTitle, action: advance)
        .position(x: Self.size.width / 2, y: OnboardingMetrics.buttonCenterY)
      corners
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .coordinateSpace(name: IslandBackdropSnapshot.coordinateSpace)
    .environment(\.islandBackdropSnapshot, backdrop)
    .clipShape(RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
    .preferredColorScheme(.dark)
    .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.08), value: page)
    .onAppear { permissions.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    .task { await fixtures.load() }
  }

  /// The art as the island's glass sees it, so tinted and clear glass differ over real colour.
  private var backdrop: IslandBackdropSnapshot? {
    OnboardingArt.shared.composite(progress: progress).map { IslandBackdropSnapshot(image: $0, canvasSize: Self.size) }
  }

  // MARK: Layers

  /// Darkens the lower half so the copy reads, like reflected water.
  private var shade: some View {
    VStack(spacing: 0) {
      Spacer()
      LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: Color(red: 0.04, green: 0.04, blue: 0.12).opacity(0.78), location: 0.5),
                .init(color: Color(red: 0.07, green: 0.07, blue: 0.11), location: 1)],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: 300)
    }
    .allowsHitTesting(false)
  }

  /// The top edge of the "display": a black strip the island hangs from.
  private var band: some View {
    ZStack(alignment: .top) {
      Color(red: 0.04, green: 0.04, blue: 0.06).frame(height: OnboardingMetrics.band)
      if case .island = page.hero {} else if !OnboardingRealIsland.shows(page) {
        Circle().fill(Color(white: 0.16)).frame(width: 8, height: 8).padding(.top, 12)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// The drawn island, for the island pages that are not the app's own island (live, replies).
  private var islandSize: CGSize? {
    if case .island(let size) = page.hero, !OnboardingRealIsland.shows(page) { return size }
    return nil
  }

  @ViewBuilder
  private var realIsland: some View {
    if let sample = fixtures.sample {
      OnboardingRealIsland(page: page, models: island, nowPlaying: sample, fixtures: fixtures)
        .opacity(OnboardingRealIsland.shows(page) ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: OnboardingRealIsland.shows(page))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  @ViewBuilder
  private var hero: some View {
    ZStack(alignment: .top) {
      let size = islandSize ?? CGSize(width: 190, height: 4)
      TourIsland(size: size, glass: page == .glass) {
        ZStack(alignment: .top) {
          OnboardingIslandContent(page: page, fixtures: fixtures, replies: replies)
            .frame(width: size.width, height: size.height, alignment: .top)
            .id(page).transition(.islandContent)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
      }
      .opacity(islandSize == nil ? 0 : 1)
      .animation(reduceMotion ? nil : NotchMotion.expansion(true, reduceMotion: false), value: size)
      if islandSize == nil {
        OnboardingPanelContent(page: page, fixtures: fixtures, permissions: permissions, hudStep: hudStep)
          .id(page).transition(slide)
      }
    }
    .padding(.top, OnboardingMetrics.band - 1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
  }

  private var copy: some View {
    let top = OnboardingMetrics.dotsY(rows: rows) - 4
    return VStack(spacing: 0) {
      TourDots(count: flow.pages.count, current: flow.index) { flow.go(to: $0) }
        .padding(.bottom, 20)
      Text(page.title).font(.system(size: 31, weight: .bold)).tracking(-0.3).foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .id("title-\(page.rawValue)").transition(.opacity.combined(with: .offset(y: 8)))
      Text(page.subtitle).font(.system(size: 15.5)).lineSpacing(3).multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(0.84)).frame(maxWidth: 600).fixedSize(horizontal: false, vertical: true)
        .padding(.top, 9).frame(height: 56, alignment: .top)
        .id("subtitle-\(page.rawValue)").transition(.opacity)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, top)
    .frame(maxHeight: .infinity, alignment: .top)
    .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.08), value: rows)
  }

  @ViewBuilder
  private var options: some View {
    VStack(spacing: OnboardingMetrics.rowPitch - OnboardingMetrics.rowHeight) {
      switch page {
      case .transform: TourTransformOptions()
      case .glass: TourGlassOptions()
      case .almostThere: TourLoginOption()
      case .replies: TourReplyOptions(model: replies)
      default: EmptyView()
      }
    }
    .id(page).transition(.opacity)
    .padding(.top, OnboardingMetrics.rowsTop)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var corners: some View {
    HStack {
      if page.rawValue > 0 { TourCircleButton(symbol: "chevron.left", label: "Back") { flow.step(-1) }.transition(.opacity) }
      Spacer()
      TourCircleButton(symbol: "xmark", label: "Close") { onFinish() }
    }
    .padding(.horizontal, 14).padding(.top, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func advance() {
    if flow.isLast { onFinish() } else { flow.step(1) }
  }
}

// MARK: - Option rows

/// Where Transform saves results: the real Settings value.
private struct TourTransformOptions: View {
  @State private var destination = AppSettings.shared.transformDestination

  var body: some View {
    ForEach(TransformDestination.allCases) { option in
      TourChoiceRow(symbol: option == .nextToOriginal ? "doc.on.doc.fill" : "arrow.down.circle.fill", title: option.rawValue,
                    selected: destination == option) {
        destination = option
        AppSettings.shared.transformDestination = option
      }
    }
  }
}

/// Tinted or clear glass: the real Theming setting, so the island above changes at once.
private struct TourGlassOptions: View {
  @ObservedObject private var theme = IslandTheme.shared

  var body: some View {
    TourChoiceRow(symbol: "drop.fill", title: "Tinted glass", selected: theme.tinted) { theme.setTinted(true) }
    TourChoiceRow(symbol: "drop", title: "Clear glass", selected: !theme.tinted) { theme.setTinted(false) }
  }
}

/// Open Brim at login.
private struct TourLoginOption: View {
  @State private var enabled = SMAppService.mainApp.status == .enabled
  @State private var failed = false

  var body: some View {
    TourRow(symbol: "power", title: "Start Brim at login") {
      Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.3, green: 0.55, blue: 1))
        .onChange(of: enabled) { _, on in apply(on) }
    }
    if failed {
      Text("Couldn’t change the login item. Dev builds outside Applications can fail.").font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.7))
    }
  }

  private func apply(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      AppSettings.shared.launchAtLogin = on
      failed = false
    } catch {
      failed = true
      enabled = SMAppService.mainApp.status == .enabled
    }
  }
}
