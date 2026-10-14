import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var settings: AppSettings
    @State private var hoverTask: Task<Void, Never>?
    @State private var dragOffset = CGSize.zero

    private var style: SurfaceAppearance { settings.features.style(for: model.surface) }
    private var compact: Bool {
        let threshold = model.surface == .dock ? settings.features.dockCompactThreshold : model.surface == .commandTab ? settings.features.cmdTabCompactThreshold : settings.features.compactThreshold
        return settings.layout == .list || (threshold > 0 && model.entries.count >= threshold)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(model.entries.count) \(model.entries.count == 1 ? "Window / App" : "Windows / Apps")")
                Spacer()
                if settings.features.showMassActions { Menu("All Windows") {
                    Button("Close All") { for entry in model.entries where model.isActionAvailable?(.close, entry) == true { model.perform(.close, entry: entry) } }
                    Button("Minimize All") { for entry in model.entries where entry.window?.isMinimized == false && model.isActionAvailable?(.minimize, entry) == true { model.perform(.minimize, entry: entry) } }
                }.menuStyle(.borderlessButton).fixedSize() }
                Text(model.surface == .dock ? "Click a window to switch" : model.releaseHint)
            }
            .font(.caption).foregroundStyle(.secondary)
            if settings.features.searchEnabled, model.surface != .dock {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(model.searchText.isEmpty ? "Type to search…" : model.searchText)
                        .foregroundStyle(model.searchText.isEmpty ? .secondary : .primary)
                    Spacer()
                    if !model.searchText.isEmpty { Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.font(.callout).padding(8).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if let message = model.actionMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            if model.entries.isEmpty {
                ContentUnavailableView(model.searchText.isEmpty ? "No Windows Found" : "No Matches", systemImage: "macwindow",
                    description: Text("Try another search or check window filters and permissions."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(settings.layout == .horizontal && !compact ? .horizontal : .vertical) {
                        if compact {
                            LazyVStack(spacing: settings.features.spacing / 2) { cards(compact: true) }
                        } else if settings.layout == .horizontal {
                            LazyHStack(spacing: settings.features.spacing) { cards(compact: false) }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.previewWidth), spacing: settings.features.spacing), count: model.gridColumnCount), spacing: settings.features.spacing) {
                                cards(compact: false)
                            }
                        }
                    }
                    .onChange(of: model.selectedIndex) { _, _ in
                        guard let entry = model.selectedEntry else { return }
                        if settings.features.reducedMotion { proxy.scrollTo(entry.id, anchor: .center) }
                        else { withAnimation(.easeOut(duration: settings.features.hoverScrollDuration)) { proxy.scrollTo(entry.id, anchor: .center) } }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if !style.hideContainerBackground {
                if style.opaqueBackground { Color(hex: style.backgroundHex) }
                else { PanelMaterial(style: settings.features.material).saturation(style.glassSaturation).blur(radius: style.glassBlur) }
            }
        }
        .opacity(settings.features.backgroundOpacity)
        .clipShape(RoundedRectangle(cornerRadius: settings.features.cornerRadius + 8))
        .overlay { RoundedRectangle(cornerRadius: settings.features.cornerRadius + 8).stroke(.white.opacity(style.borderOpacity), lineWidth: style.borderWidth) }
        .shadow(color: .black.opacity(style.showShadow ? style.shadowOpacity : 0), radius: style.shadowRadius)
        .preferredColorScheme(style.appearance == .system ? nil : style.appearance == .dark ? .dark : .light)
        .coordinateSpace(name: "switcher")
        .onPreferenceChange(CardFramesKey.self) { frames in
            if model.cardFrames != frames { model.cardFrames = frames; model.onVisibleEntriesChanged?() }
        }
        .onDisappear { hoverTask?.cancel() }
    }
    @ViewBuilder
    private func cards(compact: Bool) -> some View {
        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
            EntryCard(entry: entry, selected: index == model.selectedIndex, compact: compact,
                size: CGSize(width: model.previewWidth, height: model.previewHeight), features: settings.features, style: style,
                showTitles: settings.showWindowTitles, action: { model.perform($0, entry: entry) },
                available: { model.isActionAvailable?($0, entry) ?? false })
            .background(GeometryReader { geometry in Color.clear.preference(key: CardFramesKey.self, value: [entry.id: geometry.frame(in: .named("switcher"))]) })
            .id(entry.id)
            .onTapGesture { model.select(index); model.commit() }
            .onHover { inside in
                hoverTask?.cancel()
                if inside && settings.features.hoverSelection { model.select(index) }
                if inside && model.surface == .dock && settings.features.dockHoverFocus {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(settings.features.dockHoverFocusDelay))
                        guard !Task.isCancelled else { return }
                        model.perform(.focus, entry: entry)
                    }
                }
            }
            .onDrag { NSItemProvider(object: entry.id as NSString) }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let identity = value as? String else { return }
                    Task { @MainActor in
                        var order = settings.features.persistedOrder.isEmpty ? model.sourceEntries.map(\.id) : settings.features.persistedOrder
                        order.removeAll { $0 == identity }
                        order.insert(identity, at: min(index, order.count))
                        settings.features.persistedOrder = order; settings.features.sortOrder = .persistent
                    }
                }
                return true
            }
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                guard settings.features.previewGestures, abs(value.translation.height) > settings.features.swipeThreshold else { return }
                model.perform(value.translation.height < 0 ? settings.features.swipeUpAction : settings.features.swipeDownAction, entry: entry)
            })
        }
    }
}

struct PanelMaterial: View {
    let style: PreviewMaterial
    @ViewBuilder var body: some View {
        switch style {
        case .clear: Color.black.opacity(0.25)
        case .frosted: Rectangle().fill(.ultraThickMaterial)
        case .glass:
            if #available(macOS 26, *) { Color.clear.glassEffect(.regular, in: Rectangle()) }
            else { Rectangle().fill(.ultraThinMaterial) }
        }
    }
}

private struct EntryCard: View {
    let entry: SelectionEntry
    let selected: Bool
    let compact: Bool
    let size: CGSize
    let features: FeatureSettings
    let style: SurfaceAppearance
    let showTitles: Bool
    let action: (WindowAction) -> Void
    let available: (WindowAction) -> Bool
    @State private var peeking = false
    @State private var hovered = false
    private func visible(_ visibility: ContentVisibility) -> Bool { visibility != .never && (visibility != .hover || hovered) }
    private var controlsShown: Bool { features.showControls && visible(style.controlsVisibility) && !(compact && style.compactHideControls) }
    var body: some View {
        VStack(spacing: 0) {
            if style.titleAbovePreview { metadata }
            if !compact {
                ZStack(alignment: style.controlsOnRight ? (style.controlsAtTop ? .topTrailing : .bottomTrailing) : (style.controlsAtTop ? .topLeading : .bottomLeading)) {
                    Color.black.opacity(0.12)
                    if let image = entry.window?.thumbnail {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else { Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 54, height: 54) }
                    if controlsShown && style.embedControls { controls.padding(6) }
                }.frame(width: size.width, height: size.height).clipped()
            }
            if !style.titleAbovePreview { metadata }
        }
        .frame(width: compact ? nil : size.width)
        .background { if !style.hideCardBackground { Color.white.opacity(selected ? style.selectedOpacity : 0.05) } }
        .background {
            if style.gradientEnabled && selected {
                TimelineView(.animation(paused: features.reducedMotion)) { timeline in
                    let phase = features.reducedMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * style.gradientSpeed)
                    LinearGradient(colors: [Color(hex: style.gradientStartHex), Color(hex: style.gradientEndHex)],
                        startPoint: UnitPoint(x: 0, y: (phase + 1) / 2), endPoint: UnitPoint(x: 1, y: (1 - phase) / 2))
                        .blur(radius: style.gradientBlur).opacity(0.25)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: features.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: features.cornerRadius).strokeBorder(selected ? Color(hex: style.highlightHex) : .white.opacity(style.borderOpacity), lineWidth: selected ? 3 : style.borderWidth) }
        .opacity(selected ? 1 : style.unselectedOpacity)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.appName), \(entry.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .popover(isPresented: $peeking) {
            if let image = entry.window?.thumbnail { Image(nsImage: image).resizable().scaledToFit().frame(width: 800, height: 500).padding() }
        }
    }
    private var metadata: some View {
        HStack(spacing: 8) {
            Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: style.iconSize, height: style.iconSize)
            if !style.iconOnly {
                VStack(alignment: .leading) {
                    if showTitles && visible(style.titleVisibility) {
                        OverflowTitle(text: entry.title, overflow: style.titleOverflow, size: style.titleFontSize, reducedMotion: features.reducedMotion)
                    }
                    if features.showAppHeader && style.showHeader && (!compact || style.compactAppAndTitle) {
                        Text(entry.appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if features.showBadges && style.statusBadges {
                        HStack(spacing: 4) {
                            if entry.window == nil { Text("No open windows") }
                            if entry.window?.isMinimized == true { Text("Minimized") }
                            if entry.window?.isHidden == true { Text("Hidden") }
                            if entry.window?.isFullscreen == true { Text("Full screen") }
                        }.font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    if style.spaceBadges, let spaces = entry.window?.spaceIDs, !spaces.isEmpty {
                        Text("Space \(spaces.map(String.init).joined(separator: ", "))").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if controlsShown && (compact || !style.embedControls) { controls }
            Menu {
                ForEach(WindowAction.allCases) { item in Button(item.title) { action(item) }.disabled(!available(item)) }
                Divider()
                Button("Large Preview") { peeking = true }.disabled(entry.window?.thumbnail == nil)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("Window actions")
        }.padding(8).frame(minHeight: compact ? style.itemHeight : 44)
    }
    private var controls: some View {
        HStack(spacing: 4) {
            ForEach(style.enabledActions) { item in
                Button { action(item) } label: {
                    Image(systemName: icon(item)).font(.system(size: 12 * style.controlScale))
                        .foregroundStyle(style.monochromeControls ? Color.primary : tint(item))
                }.buttonStyle(.plain).disabled(!available(item)).accessibilityLabel(item.title).help(item.title)
            }
        }.padding(4).background(.regularMaterial, in: Capsule())
            .opacity(style.controlsVisibility == .dimmed && !hovered ? 0.4 : 1)
    }
    private func icon(_ action: WindowAction) -> String {
        switch action { case .close: "xmark.circle.fill"; case .minimize: "minus.circle.fill"; case .fullscreen: "arrow.up.left.and.arrow.down.right.circle.fill"; case .quit: "power.circle.fill"; default: "circle" }
    }
    private func tint(_ action: WindowAction) -> Color {
        switch action { case .close, .quit: .red; case .minimize: .yellow; default: .green }
    }
}
private struct OverflowTitle: View {
    let text: String
    let overflow: TitleOverflow
    let size: Double
    let reducedMotion: Bool
    var body: some View {
        if overflow == .marquee && !reducedMotion {
            TimelineView(.animation) { timeline in
                Text(text).font(.system(size: size, weight: .semibold)).fixedSize(horizontal: true, vertical: false)
                    .offset(x: -max(0, sin(timeline.date.timeIntervalSinceReferenceDate / 3)) * Double(max(0, text.count - 22)) * 3)
                    .frame(maxWidth: .infinity, alignment: .leading).clipped()
            }.frame(height: size + 4)
        } else {
            Text(text).font(.system(size: size, weight: .semibold)).lineLimit(1)
                .truncationMode(overflow == .head ? .head : overflow == .middle ? .middle : .tail)
        }
    }
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
