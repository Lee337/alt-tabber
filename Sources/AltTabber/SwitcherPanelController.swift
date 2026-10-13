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

    func show() {
        resizeAndCenter()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func resizeAndCenter() {
        let screen = screenUnderPointer() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let metrics = SwitcherPanelLayoutMetrics.calculate(
            itemCount: model.windows.count,
            screenSize: visibleFrame.size,
            layout: settings.layout,
            preferredPreviewSize: settings.previewSize,
            requestedColumnCount: settings.gridColumns
        )
        model.setGridColumnCount(metrics.columnCount)
        model.setPreviewSize(metrics.previewSize)
        let origin = NSPoint(
            x: visibleFrame.midX - metrics.panelSize.width / 2,
            y: visibleFrame.midY - metrics.panelSize.height / 2
        )
        panel.setFrame(
            NSRect(origin: origin, size: metrics.panelSize),
            display: true
        )
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
