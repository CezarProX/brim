import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Home: an iOS-style widget grid inside the island. One row of four units per page (a small
/// widget is one unit, a medium two); more pages slide sideways (or up and down) with dots beneath.
/// The island's width is computed from the grid (`HomeWidgetStore.shelfWidth`), so nothing is cut.
/// Editing wobbles the widgets, adds remove badges and resize handles, and shows a dock of every widget.
@MainActor
struct IslandWidgetShelf: View {
  @ObservedObject var layout: HomeWidgetStore
  @ObservedObject var center: ActivityCenter
  @ObservedObject var store: ShelfStore
  @ObservedObject var nowPlaying: NowPlayingModel
  let openTool: (IslandActivity) -> Void
  let showShelf: () -> Void
  @State private var snapshot: [HomeWidgetItem] = []
  @State private var scrolledPage: Int? = 0
  @State private var hovered = false
  @State private var frames: [HomeWidget: CGRect] = [:]
  @State private var drag: HomeEditDrag?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var motion: Animation? { NotchMotion.layout(reduceMotion: reduceMotion) }

  var body: some View {
    VStack(spacing: IslandSpace.m) {
      if layout.items.isEmpty && !layout.isEditing {
        Button("Add widgets") { beginEditing() }
          .buttonStyle(IslandPillStyle(compact: true))
          .frame(maxWidth: .infinity, minHeight: HomeWidgetStore.rowHeight)
      } else {
        grid
          .padding(.horizontal, layout.isEditing ? HomeWidgetStore.editMargin : 0)
          .padding(.top, layout.isEditing ? HomeWidgetStore.editMargin : 0)
      }
      if layout.isEditing {
        dock.padding(.top, layout.editingDotsReserve).transition(.islandDrop)
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .background { if layout.isEditing { IslandScrollRegions.Marker(mode: .blocker) } }
    .coordinateSpace(name: HomeWidgetDrag.space)
    .onPreferenceChange(HomeWidgetFramesKey.self) { frames = $0 }
    .overlay(alignment: .topLeading) { dragOverlay }
    .animation(motion, value: layout.items)
    .animation(motion, value: layout.isEditing)
    // Editing is one step away, as on an iPhone home screen: a pencil on hover, a long press,
    // or right-click on any widget (the tab bar's Customize Home still works too).
    .overlay(alignment: .topTrailing) {
      if hovered, !layout.isEditing, !layout.items.isEmpty {
        Button(action: beginEditing) {
          Image(systemName: "pencil").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandInk.primary)
            .frame(width: 22, height: 22).background(IslandFill.raised, in: Circle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.86))
        .help("Edit Home")
        .accessibilityLabel("Edit Home")
        .offset(x: 8, y: -8)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
    .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovered = inside } }
  }

  // MARK: Grid

  /// Mouse-wheel paging over the Home grid.
  private func stepGridPage(_ delta: Int) {
    let count = layout.pages.count
    guard count > 1 else { return }
    layout.page = min(max(layout.page + delta, 0), count - 1)
  }

  /// One page, or pages that scroll sideways (or up and down) with dots beneath.
  @ViewBuilder private var grid: some View {
    let pages = layout.pages
    if pages.count <= 1 {
      row(pages.first ?? [], leading: layout.isEditing)
    } else {
      let vertical = layout.pagesVertically
      // The scroll view clips, so give it a margin that the edit badges, handles and outlines can use.
      let margin = HomeWidgetStore.editMargin
      ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
        let content = ForEach(pages.indices, id: \.self) { index in
          // A page that isn't full sits in the middle, so a lone widget never hugs one edge of an empty
          // island; while editing, pages fill from the leading edge as on iOS.
          row(pages[index], leading: layout.isEditing).padding(margin).id(index)
        }
        Group {
          if vertical { LazyVStack(spacing: 0) { content } } else { LazyHStack(spacing: 0) { content } }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      .scrollPosition(id: $scrolledPage)
      .frame(width: layout.gridWidth + 2 * margin, height: HomeWidgetStore.rowHeight + 2 * margin)
      .padding(-margin)
      .background { if !vertical { IslandScrollRegions.Marker(mode: .pager(step: stepGridPage)) } }
      .onChange(of: scrolledPage) { _, value in if let value { layout.page = value } }
      .onChange(of: layout.page) { _, value in withAnimation(motion) { scrolledPage = value } }
      .overlay(alignment: vertical ? .trailing : .bottom) {
        pageDots(count: pages.count, vertical: vertical)
          .offset(x: vertical ? 14 : 0, y: vertical ? 0 : layout.isEditing ? 26 : 15)
      }
    }
  }

  /// A page of the grid, exactly `gridWidth` wide. Pages fill from the leading edge, as on iOS;
  /// a lone page narrower than the island's minimum sits in the middle.
  private func row(_ items: [HomeWidgetItem], leading: Bool) -> some View {
    HStack(alignment: .top, spacing: HomeWidgetGrid.gap) {
      ForEach(items) { item in
        cell(item).transition(.scale(scale: 0.7).combined(with: .opacity))
      }
    }
    .frame(width: layout.gridWidth, height: HomeWidgetStore.rowHeight, alignment: leading ? .topLeading : .top)
  }

  private func pageDots(count: Int, vertical: Bool) -> some View {
    let dots = ForEach(0..<count, id: \.self) { index in
      Button { layout.page = index } label: {
        Circle().fill(index == layout.page ? Color.white : IslandInk.tertiary).frame(width: 5, height: 5)
          .padding(3).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Widgets page \(index + 1)")
    }
    return Group { if vertical { VStack(spacing: 0) { dots } } else { HStack(spacing: 0) { dots } } }
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: layout.page)
  }

  private func cell(_ item: HomeWidgetItem) -> some View {
    let widget = item.widget
    let editing = layout.isEditing
    return HomeWidgetContent(
      widget: widget, size: item.size, center: center, store: store, nowPlaying: nowPlaying,
      openTool: openTool, showShelf: showShelf
    )
    .frame(width: item.size.width, height: HomeWidgetStore.rowHeight, alignment: .topLeading)
    .allowsHitTesting(!editing)
    .overlay {
      if editing {
        RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous)
          .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
          .padding(-4)
          .transition(.opacity)
      }
    }
    .overlay(alignment: .topLeading) {
      if editing {
        HomeRemoveBadge(title: widget.title) { withAnimation(motion) { layout.toggle(widget) } }
          .offset(x: -9, y: -9)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if editing, widget.sizes.count > 1 {
        let target: HomeWidgetSize = item.size == .small ? .medium : .small
        HomeResizeHandle(title: widget.title, grows: target > item.size,
                         enabled: layout.canResize(widget, to: target)) {
          withAnimation(motion) { layout.setSize(widget, target) }
        }
        .offset(x: 9, y: 9)
        .transition(.scale.combined(with: .opacity))
      }
    }
    .modifier(HomeJiggle(active: editing && !reduceMotion && drag?.widget != widget, seed: widget.rawValue.count))
    .contentShape(Rectangle())
    .reportsHomeWidgetFrame(widget)
    // While it is picked up, the grid keeps only its gap (which slides as the others make room);
    // the widget itself rides under the pointer in `dragOverlay`, untouched by the layout spring.
    // Faded, not hidden: SwiftUI stops delivering events to a view at opacity 0, ending the drag.
    .opacity(isLifted(widget) ? 0.02 : 1)
    .gesture(editing ? reorderGesture(widget) : nil)
    .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
      if !layout.isEditing { beginEditing() }
    })
    .contextMenu { if !editing { contextMenu(item) } }
  }

  /// Right-click on a widget: its sizes (as iOS's long-press menu), editing and removal.
  @ViewBuilder private func contextMenu(_ item: HomeWidgetItem) -> some View {
    if item.widget.sizes.count > 1 {
      ForEach(item.widget.sizes, id: \.self) { size in
        Toggle(isOn: Binding(get: { item.size == size }, set: { _ in layout.setSize(item.widget, size) })) {
          Text(size == .small ? "Small size" : "Medium size")
        }
        .disabled(size != item.size && !layout.canResize(item.widget, to: size))
      }
      Divider()
    }
    Button("Edit Home") { beginEditing() }
    Button("Remove \(item.widget.title)", role: .destructive) { layout.toggle(item.widget) }
  }

  // MARK: Dock

  private var dock: some View {
    HStack(alignment: .top, spacing: 10) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(HomeWidget.allCases) { widget in dockItem(widget) }
        }
        .padding(.horizontal, 4)
      }
      .islandScrollRegion()
      .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.02),
                                   .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing))
      Button {
        layout.restore(snapshot)
        endEditing()
      } label: {
        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
          .frame(width: 32, height: 32).background(IslandFill.hover, in: Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.88))
      .accessibilityLabel("Cancel")
      Button(action: endEditing) {
        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
          .frame(width: 32, height: 32).background(Color.blue, in: Circle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.88))
      .accessibilityLabel("Done")
    }
    .frame(height: HomeWidgetStore.dockHeight - IslandSpace.m)
    .onAppear { snapshot = layout.items }
  }

  /// A dock icon, one per widget: click adds it (at its default size) or removes it; drag it onto
  /// the grid to drop it exactly there.
  private func dockItem(_ widget: HomeWidget) -> some View {
    let added = layout.widgets.contains(widget)
    let addable = added || layout.canAdd(widget)
    return VStack(spacing: 3) {
      HomeWidgetIcon(widget: widget, size: 36)
        .overlay(alignment: .bottomTrailing) {
          if added {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
              .symbolRenderingMode(.palette).foregroundStyle(.white, Color.blue)
              .offset(x: 4, y: 4).transition(.scale)
          }
        }
      Text(widget.title).font(.system(size: 9, weight: .medium)).foregroundStyle(IslandInk.secondary)
        .lineLimit(1).frame(width: 46)
    }
    .opacity(drag?.widget == widget && drag?.fromDock == true ? 0.35 : addable ? 1 : 0.35)
    .contentShape(Rectangle())
    .onTapGesture { withAnimation(motion) { layout.toggle(widget) } }
    .gesture(added ? nil : dockDragGesture(widget))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(added ? "Remove \(widget.title)" : "Add \(widget.title)")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { layout.toggle(widget) }
  }

  // MARK: Dragging

  /// The widgets the grid shows right now (the page in view when they overflow one page).
  private var visibleOrder: [HomeWidget] {
    let pages = layout.pages
    guard pages.count > 1 else { return layout.widgets }
    return pages[min(layout.page, pages.count - 1)].map(\.widget)
  }

  private func isLifted(_ widget: HomeWidget) -> Bool { drag?.widget == widget && drag?.fromDock == false }

  /// Pick a widget up and the others make room as it passes their middles.
  private func reorderGesture(_ widget: HomeWidget) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named(HomeWidgetDrag.space))
      .onChanged { value in
        if drag?.widget != widget {
          let frame = frames[widget] ?? .zero
          drag = HomeEditDrag(widget: widget, fromDock: false, location: value.location,
                              grab: CGSize(width: value.startLocation.x - frame.midX,
                                           height: value.startLocation.y - frame.midY))
        }
        drag?.location = value.location
        let order = visibleOrder
        let index = HomeWidgetDrag.insertionIndex(x: value.location.x, order: order, frames: frames, dragging: widget)
        let global = HomeWidgetDrag.globalIndex(index, visible: order, all: layout.widgets, dragging: widget)
        let page = layout.pages.count > 1 ? min(layout.page, layout.pages.count - 1) : 0
        withAnimation(motion) { layout.place(widget, at: global, keepingPage: page) }
      }
      .onEnded { _ in withAnimation(motion) { drag = nil } }
  }

  /// Drag a dock icon up onto the grid; it lands in the gap under the pointer.
  private func dockDragGesture(_ widget: HomeWidget) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named(HomeWidgetDrag.space))
      .onChanged { value in
        if drag?.widget != widget {
          drag = HomeEditDrag(widget: widget, fromDock: true, location: value.location, grab: .zero)
        }
        drag?.location = value.location
      }
      .onEnded { value in
        if overRow(value.location), layout.canAdd(widget) {
          let order = visibleOrder
          let index = HomeWidgetDrag.insertionIndex(x: value.location.x, order: order, frames: frames, dragging: nil)
          let global = HomeWidgetDrag.globalIndex(index, visible: order, all: layout.widgets, dragging: widget)
          withAnimation(motion) { layout.place(widget, at: global) }
        }
        withAnimation(.easeOut(duration: 0.15)) { drag = nil }
      }
  }

  private func overRow(_ point: CGPoint) -> Bool {
    let bottom = frames.values.map(\.maxY).max() ?? (HomeWidgetStore.editMargin + HomeWidgetStore.rowHeight)
    return point.y < bottom + 12
  }

  /// The icon following the pointer out of the dock, and the bar showing where it will land.
  @ViewBuilder private var dragOverlay: some View {
    if let drag, !drag.fromDock, let item = layout.items.first(where: { $0.widget == drag.widget }) {
      HomeWidgetContent(
        widget: item.widget, size: item.size, center: center, store: store, nowPlaying: nowPlaying,
        openTool: openTool, showShelf: showShelf
      )
      .frame(width: item.size.width, height: HomeWidgetStore.rowHeight, alignment: .topLeading)
      .scaleEffect(1.06)
      .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
      .position(x: drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
      .allowsHitTesting(false)
    } else if let drag, drag.fromDock {
      ZStack(alignment: .topLeading) {
        if overRow(drag.location), layout.canAdd(drag.widget),
           let x = HomeWidgetDrag.caretX(
             index: HomeWidgetDrag.insertionIndex(x: drag.location.x, order: visibleOrder, frames: frames, dragging: nil),
             order: visibleOrder, frames: frames, dragging: nil),
           let top = frames.values.map(\.minY).min() {
          Capsule().fill(Color.blue).frame(width: 4, height: HomeWidgetStore.rowHeight)
            .position(x: x, y: top + HomeWidgetStore.rowHeight / 2)
            .transition(.opacity)
        }
        HomeWidgetIcon(widget: drag.widget, size: 36).scaleEffect(1.25)
          .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
          .position(drag.location)
      }
      .allowsHitTesting(false)
    }
  }

  private func beginEditing() {
    withAnimation(motion) { layout.isEditing = true }
  }

  private func endEditing() {
    withAnimation(motion) { layout.isEditing = false }
  }
}
