import AppKit
import SwiftUI

struct SwitcherPanelLayoutMetrics {
    let panelSize: CGSize
    let previewSize: CGSize
    let columnCount: Int

    static func calculate(
        itemCount: Int,
        screenSize: CGSize,
        layout: SwitcherLayout,
        preferredPreviewSize: PreviewSize,
        requestedColumnCount: Int
    ) -> SwitcherPanelLayoutMetrics {
        let spacing: CGFloat = 12
        let panelChromeWidth: CGFloat = 40
        let panelChromeHeight: CGFloat = 70
        let metadataHeight: CGFloat = 44
        let safeItemCount = max(itemCount, 1)
        let preferredWidth = preferredPreviewSize.width
        let preferredHeight = preferredPreviewSize.height
        let previewAspectRatio = preferredWidth / preferredHeight

        let maximumPanelWidth = max(320, screenSize.width - 48)
        let panelWidth = min(
            maximumPanelWidth,
            max(640, screenSize.width * 0.92)
        )
        let maximumPanelHeight = min(
            max(280, screenSize.height - 48),
            max(300, screenSize.height * 0.86)
        )
        let contentWidth = max(preferredWidth, panelWidth - panelChromeWidth)

        if itemCount == 0 {
            return SwitcherPanelLayoutMetrics(
                panelSize: CGSize(width: min(panelWidth, 720), height: 300),
                previewSize: CGSize(width: preferredWidth, height: preferredHeight),
                columnCount: 1
            )
        }

        if layout == .horizontal {
            let maximumVisibleItems = max(
                1,
                Int((contentWidth + spacing) / (preferredWidth + spacing))
            )
            let visibleItems = min(safeItemCount, maximumVisibleItems)
            let widthFromAvailableSpace = (
                contentWidth - CGFloat(max(0, visibleItems - 1)) * spacing
            ) / CGFloat(visibleItems)
            let maximumPreviewHeight = max(
                preferredHeight,
                maximumPanelHeight - panelChromeHeight - metadataHeight
            )
            let cardWidth = max(
                preferredWidth,
                min(widthFromAvailableSpace, maximumPreviewHeight * previewAspectRatio)
            )
            let previewHeight = cardWidth / previewAspectRatio
            return SwitcherPanelLayoutMetrics(
                panelSize: CGSize(
                    width: panelWidth,
                    height: min(
                        maximumPanelHeight,
                        previewHeight + metadataHeight + panelChromeHeight
                    )
                ),
                previewSize: CGSize(width: cardWidth, height: previewHeight),
                columnCount: safeItemCount
            )
        }

        let maximumColumns = max(
            1,
            Int((contentWidth + spacing) / (preferredWidth + spacing))
        )
        let columns = min(
            safeItemCount,
            min(max(1, requestedColumnCount), maximumColumns)
        )
        let rows = Int(ceil(Double(safeItemCount) / Double(columns)))
        let widthFromAvailableSpace = (
            contentWidth - CGFloat(max(0, columns - 1)) * spacing
        ) / CGFloat(columns)

        let cardWidth: CGFloat
        if rows == 1 {
            let maximumPreviewHeight = max(
                preferredHeight,
                maximumPanelHeight - panelChromeHeight - metadataHeight
            )
            cardWidth = max(
                preferredWidth,
                min(widthFromAvailableSpace, maximumPreviewHeight * previewAspectRatio)
            )
        } else {
            cardWidth = max(preferredWidth, widthFromAvailableSpace)
        }

        let previewHeight = cardWidth / previewAspectRatio
        let contentHeight = CGFloat(rows) * (previewHeight + metadataHeight)
            + CGFloat(max(0, rows - 1)) * spacing
            + panelChromeHeight

        return SwitcherPanelLayoutMetrics(
            panelSize: CGSize(
                width: panelWidth,
                height: min(maximumPanelHeight, contentHeight)
            ),
            previewSize: CGSize(width: cardWidth, height: previewHeight),
            columnCount: columns
        )
    }
}

@MainActor
final class SwitcherPanelController {
    private let model: SwitcherModel
    private let settings: AppSettings
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var hasEmbeddedWidgets = false

    var isVisible: Bool { panel.isVisible }

    init(model: SwitcherModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        let rootView = SwitcherView(model: model, settings: settings)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 864, height: 408),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        hostingController.view.autoresizingMask = [.width, .height]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
    }

    var frame: CGRect { panel.frame }
    var containsPointer: Bool { panel.isVisible && panel.frame.contains(NSEvent.mouseLocation) }

    var visibleWindows: [WindowItem] {
        let viewport = CGRect(origin: .zero, size: panel.frame.size)
        return model.entries.filter { model.cardFrames[$0.id]?.intersects(viewport) == true }.compactMap(\.window)
    }

    func entryAtPointer() -> SelectionEntry? {
        let point = NSEvent.mouseLocation
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        return model.entries.first { model.cardFrames[$0.id]?.contains(local) == true }
    }

    func embed(calendar: CalendarWidgetModel? = nil, media: MediaWidgetModel? = nil) {
        hasEmbeddedWidgets = calendar != nil || media != nil
        if hasEmbeddedWidgets {
            panel.contentViewController = NSHostingController(rootView: EmbeddedWidgetView(switcher: model, settings: settings, calendar: calendar, media: media))
        } else {
            panel.contentViewController = NSHostingController(rootView: SwitcherView(model: model, settings: settings))
        }
    }

    func show(near dockFrame: CGRect? = nil) {
        hideTask?.cancel(); panel.alphaValue = 1
        resizeAndCenter()
        if let dockFrame {
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let anchor = WindowGeometry.accessibilityFrame(dockFrame, desktopTop: top)
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let width = min(hasEmbeddedWidgets ? 1150 : 850, visible.width - 40)
                let height = min(480, visible.height - 40)
                var x = anchor.midX - width / 2
                var y = anchor.maxY + settings.features.dockBuffer
                if anchor.midX < visible.minX + 100 { x = anchor.maxX + settings.features.dockBuffer; y = anchor.midY - height / 2 }
                else if anchor.midX > visible.maxX - 100 { x = anchor.minX - width - settings.features.dockBuffer; y = anchor.midY - height / 2 }
                panel.setFrame(CGRect(x: max(visible.minX, min(x, visible.maxX - width)),
                    y: max(visible.minY, min(y, visible.maxY - height)), width: width, height: height), display: true)
                let columns = max(1, min(hasEmbeddedWidgets ? 2 : settings.features.dockStyle.maxColumns, model.entries.count))
                model.setGridColumnCount(columns)
                model.setPreviewSize(CGSize(width: max(120, (width - (hasEmbeddedWidgets ? 400 : 60)) / CGFloat(columns)), height: 150))
            }
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        hideTask?.cancel()
        let duration = settings.features.reducedMotion ? 0 : settings.features.fadeDuration
        guard duration > 0 else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in context.duration = duration; panel.animator().alphaValue = 0 }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func resizeAndCenter() {
        let screen: NSScreen?
        switch settings.features.placement {
        case .pointer: screen = screenUnderPointer() ?? NSScreen.main
        case .main: screen = NSScreen.screens.first
        case .pinned: screen = NSScreen.screens.first { String($0.displayID) == settings.features.pinnedDisplay } ?? NSScreen.main
        case .activeWindow:
            screen = NSScreen.screens.first { $0.displayID == model.windows.first?.displayID } ?? NSScreen.main
        }
        guard let visibleFrame = screen?.visibleFrame else { return }
        let metrics = SwitcherPanelLayoutMetrics.calculate(
            itemCount: model.entries.count,
            screenSize: visibleFrame.size,
            layout: settings.layout,
            preferredPreviewSize: settings.previewSize,
            requestedColumnCount: model.surface == .switcher ? min(settings.gridColumns, settings.features.switcherStyle.maxColumns) : settings.features.style(for: model.surface).maxColumns
        )
        model.setGridColumnCount(metrics.columnCount)
        if settings.features.previewWidth > 0 {
            let width = settings.features.previewWidth
            let height = settings.features.keepAspectRatio ? width * metrics.previewSize.height / metrics.previewSize.width : max(60, settings.features.previewHeight)
            model.setPreviewSize(CGSize(width: width, height: height))
        } else { model.setPreviewSize(metrics.previewSize) }
        let origin = NSPoint(
            x: visibleFrame.midX - metrics.panelSize.width / 2 + visibleFrame.width * settings.features.horizontalOffset / 100,
            y: (settings.features.anchorTop ? visibleFrame.maxY - metrics.panelSize.height : visibleFrame.midY - metrics.panelSize.height / 2) + visibleFrame.height * settings.features.verticalOffset / 100
        )
        var panelSize = metrics.panelSize
        let style = settings.features.style(for: model.surface)
        panelSize.height = min(panelSize.height, CGFloat(style.maxRows) * (model.previewHeight + 56 + settings.features.spacing) + 120)
        panel.setFrame(
            NSRect(origin: origin, size: panelSize),
            display: true
        )
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
