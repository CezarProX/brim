import SwiftUI

/// Action Ring editor: pick how it opens, switch between up to three rings, drag actions onto
/// slots, and customize each slot's title, icon, color and action.
struct RingSettingsSection: View {
  @State private var layout = AppSettings.shared.ringLayout
  @State private var ringIndex = 0
  @State private var selected: Int?
  @State private var mode = AppSettings.shared.ringTriggerMode
  @State private var holdModifier = AppSettings.shared.ringHoldModifier

  var body: some View {
    Group {
      opening
      ringsEditor
      palette
    }
  }

  // MARK: Opening

  private var opening: some View {
    group("Action Ring") {
      Text("Press ⌥⌘R to show the ring at the pointer. Scroll or press 1, 2 or 3 to switch rings.")
        .font(.footnote).foregroundStyle(.secondary)
      Picker("Mode", selection: $mode) {
        ForEach(RingTriggerMode.allCases) { Text($0.title).tag($0) }
      }
      .onChange(of: mode) { _, value in AppSettings.shared.ringTriggerMode = value }
      Picker("Open by holding", selection: $holdModifier) {
        ForEach(RingHoldModifier.allCases) { Text($0.title).tag($0) }
      }
      .onChange(of: holdModifier) { _, value in
        AppSettings.shared.ringHoldModifier = value
        RingMenuController.shared.start()
      }
      Text("A four-finger tap would need a private multitouch framework, so Brim uses a held modifier instead: hold it for half a second, move to a slot and let go. This needs Input Monitoring access.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  // MARK: Rings and slots

  private var ringsEditor: some View {
    group("Rings") {
      HStack(spacing: 8) {
        Picker("Ring", selection: $ringIndex) {
          ForEach(layout.rings.indices, id: \.self) { Text(layout.rings[$0].name).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
        Button { commit(layout.addingRing()); ringIndex = layout.rings.count - 1 } label: { Image(systemName: "plus") }
          .disabled(!layout.canAddRing).help("Add a ring (up to 3)")
        Button { commit(layout.removingRing(at: ringIndex)); ringIndex = min(ringIndex, layout.rings.count - 1) } label: {
          Image(systemName: "minus")
        }
        .disabled(layout.rings.count < 2).help("Remove this ring")
      }
      TextField("Name", text: Binding(
        get: { layout.rings[safe: ringIndex]?.name ?? "" },
        set: { commit(layout.renamingRing(at: ringIndex, to: $0)) })
      )
      .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
      slotGrid
      if let selected, let slot = layout.rings[safe: ringIndex]?.slots[selected] {
        RingSlotEditor(slot: slot) { commit(layout.setting($0, ring: ringIndex, index: selected)) }
          .id(slot.id)
      } else {
        Text("Click a slot to edit it, or drag slots to rearrange them.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private var slotGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
      ForEach(0..<RingPage.slotCount, id: \.self) { index in slotCell(index) }
    }
  }

  private func slotCell(_ index: Int) -> some View {
    let slot = layout.rings[safe: ringIndex]?.slots[index]
    return ZStack {
      RoundedRectangle(cornerRadius: 14)
        .fill(slot == nil ? Color.clear : Color.black.opacity(0.7))
        .overlay {
          RoundedRectangle(cornerRadius: 14)
            .strokeBorder(selected == index ? Color.accentColor : Color.secondary.opacity(0.35),
                          style: StrokeStyle(lineWidth: selected == index ? 2 : 1, dash: slot == nil ? [4, 3] : []))
        }
      if let slot {
        VStack(spacing: 3) {
          Image(systemName: slot.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(slot.color)
          Text(slot.title).font(.system(size: 9, weight: .medium)).lineLimit(1).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 3)
      } else {
        Text("\(index + 1)").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .frame(width: 64, height: 56)
    .contentShape(RoundedRectangle(cornerRadius: 14))
    .onTapGesture { selected = index }
    .draggable(RingDropPayload.slot(ring: ringIndex, index: index).text)
    .dropDestination(for: String.self) { items, _ in
      guard let payload = items.first.flatMap(RingDropPayload.init) else { return false }
      commit(layout.applying(payload, toRing: ringIndex, index: index))
      selected = index
      return true
    }
    .accessibilityLabel(slot?.title ?? "Empty slot \(index + 1)")
  }

  // MARK: Palette

  private var palette: some View {
    group("Actions") {
      Text("Drag an action onto a slot.").font(.footnote).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
        ForEach(Self.paletteEntries, id: \.text) { entry in chip(entry) }
      }
    }
  }

  static let paletteEntries: [RingDropPayload] =
    RingBuiltIn.allCases.map { .action(kind: .builtIn, argument: $0.rawValue) }
    + RingMedia.allCases.map { .action(kind: .media, argument: $0.rawValue) }
    + RingToggle.allCases.map { .action(kind: .toggle, argument: $0.rawValue) }
    + [
      .action(kind: .openURL, argument: "https://"), .action(kind: .shortcut, argument: ""),
      .action(kind: .openApp, argument: ""),
    ]

  private func chip(_ payload: RingDropPayload) -> some View {
    guard case .action(let kind, let argument) = payload else { return AnyView(EmptyView()) }
    let preset = RingPresets.preset(kind: kind, argument: argument)
    let title = kind == .openURL ? "Open URL" : kind == .shortcut ? "Run Shortcut" : kind == .openApp ? "Open app" : preset.title
    return AnyView(
      HStack(spacing: 6) {
        Image(systemName: preset.symbol).foregroundStyle(Color(hex: preset.colorHex) ?? .white).frame(width: 16)
        Text(title).font(.caption).lineLimit(1)
      }
      .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading).frame(height: 28)
      .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
      .draggable(payload.text)
      .onTapGesture {
        guard let selected else { return }
        commit(layout.applying(payload, toRing: ringIndex, index: selected))
      })
  }

  private func commit(_ next: RingLayout) {
    layout = next
    AppSettings.shared.ringLayout = next
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}

