import AppKit
import SwiftUI

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
        let itemCount = max(model.windows.count, 1)
        let screen = screenUnderPointer() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let spacing: CGFloat = 12
        let cardWidth = settings.previewSize.width
        let cardHeight = settings.previewSize.height + 44
        let panelChromeWidth: CGFloat = 40
        let panelChromeHeight: CGFloat = 58
        let availableWidth = max(cardWidth + panelChromeWidth, visibleFrame.width - 64)
        let minimumHeight = cardHeight + panelChromeHeight
        let availableHeight = max(minimumHeight, visibleFrame.height - 64)

        if settings.layout == .horizontal {
            let width = min(
                availableWidth,
                CGFloat(itemCount) * cardWidth
                    + CGFloat(max(0, itemCount - 1)) * spacing
                    + panelChromeWidth
            )
            model.setGridColumnCount(itemCount)
            let origin = NSPoint(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - minimumHeight / 2
            )
            panel.setFrame(
                NSRect(origin: origin, size: NSSize(width: width, height: minimumHeight)),
                display: true
            )
            return
        }

        let maximumColumns = max(
            1,
            Int((availableWidth - panelChromeWidth + spacing) / (cardWidth + spacing))
        )
        let columns = min(itemCount, min(settings.gridColumns, maximumColumns))
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        model.setGridColumnCount(columns)

        let width = CGFloat(columns) * cardWidth
            + CGFloat(max(0, columns - 1)) * spacing
            + panelChromeWidth
        let contentHeight = CGFloat(rows) * cardHeight
            + CGFloat(max(0, rows - 1)) * spacing
            + panelChromeHeight
        let height = min(availableHeight, contentHeight)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
