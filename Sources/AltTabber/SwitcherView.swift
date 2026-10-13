import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var settings: AppSettings

    private let spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.windows.isEmpty {
                ContentUnavailableView(
                    "No Windows Found",
                    systemImage: "macwindow",
                    description: Text("Open an app window and try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if settings.layout == .grid {
                grid
            } else {
                horizontalStrip
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 28, y: 14)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(model.windows.count) \(model.windows.count == 1 ? "Window" : "Windows")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Release ⌥ to switch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 18)
        .padding(.horizontal, 2)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(model.previewWidth), spacing: spacing),
            count: model.gridColumnCount
        )
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: gridColumns, alignment: .center, spacing: spacing) {
                    windowCards
                }
                .padding(4)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.selectedIndex) { _, newIndex in
                scrollToSelection(newIndex, using: proxy)
            }
        }
    }

    private var horizontalStrip: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        windowCards
                    }
                    .padding(4)
                    .frame(
                        minWidth: max(0, geometry.size.width - 8),
                        alignment: .center
                    )
                }
                .onChange(of: model.selectedIndex) { _, newIndex in
                    scrollToSelection(newIndex, using: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private var windowCards: some View {
        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, item in
            WindowCard(
                item: item,
                isSelected: index == model.selectedIndex,
                previewSize: CGSize(width: model.previewWidth, height: model.previewHeight),
                settings: settings
            )
            .id(item.id)
            .onTapGesture {
                model.select(index)
                model.commit()
            }
        }
    }

    private func scrollToSelection(_ index: Int, using proxy: ScrollViewProxy) {
        guard model.windows.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(model.windows[index].id, anchor: .center)
        }
    }
}

private struct WindowCard: View {
    let item: WindowItem
    let isSelected: Bool
    let previewSize: CGSize
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            preview
            metadata
        }
        .frame(width: previewSize.width)
        .background(Color.white.opacity(isSelected ? 0.11 : 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 3 : 1
                )
        }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.28) : .clear, radius: 9)
        .scaleEffect(isSelected ? 1.018 : 1)
        .animation(.easeOut(duration: 0.11), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.appName), \(item.displayTitle)")
    }

    private var preview: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.09), Color.black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(nsImage: item.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipped()
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                if settings.showWindowTitles {
                    Text(item.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if !settings.showWindowTitles || item.hasDistinctTitle {
                    Text(item.appName)
                        .font(.system(
                            size: settings.showWindowTitles ? 9 : 11,
                            weight: settings.showWindowTitles ? .regular : .semibold
                        ))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .background(Color.black.opacity(0.13))
    }
}
