import AppKit
import SwiftUI

@MainActor
final class ActiveAppIndicator {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    init() {
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func show(_ target: DockTarget?, style: IndicatorStyle, count: Int, settings: FeatureSettings) {
        guard let target else { hide(); return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let anchor = WindowGeometry.accessibilityFrame(target.frame, desktopTop: top)
        let height = settings.indicatorAutoSize ? max(2, min(6, target.frame.height / 12)) : settings.indicatorHeight
        panel.contentViewController = NSHostingController(rootView: IndicatorView(style: style, count: count, color: Color(hex: settings.indicatorHex), height: height))
        panel.setFrame(CGRect(x: anchor.midX - settings.indicatorLength / 2 + settings.indicatorShift, y: anchor.minY - settings.indicatorOffset - settings.indicatorHeight, width: settings.indicatorLength, height: max(settings.indicatorHeight, 16)), display: true)
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}
private struct IndicatorView: View {
    let style: IndicatorStyle
    let count: Int
    let color: Color
    let height: Double
    var body: some View {
        switch style {
        case .bar: Capsule().fill(color).frame(height: height)
        case .dots: HStack(spacing: 3) { ForEach(0..<min(6, max(1, count)), id: \.self) { _ in Circle().fill(color).frame(width: 4, height: 4) } }
        case .count: Text("\(count)").font(.system(size: 10, weight: .bold)).foregroundStyle(color)
        }
    }
}
@MainActor
final class FullSizePreviewController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<LargePreviewContent>?
    private var lastSourceSize: CGSize?
    private var lastVisibleFrame: CGRect?
    var onClose: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }
    func contentSize(near switcherFrame: CGRect, sourceSize: CGSize) -> CGSize {
        let display = NSScreen.screens.max { left, right in
            let lhs = left.frame.intersection(switcherFrame)
            let rhs = right.frame.intersection(switcherFrame)
            return lhs.width * lhs.height < rhs.width * rhs.height
        } ?? NSScreen.main
        return FullSizePreviewLayout.frame(visibleFrame: display?.visibleFrame ?? switcherFrame,
                                           sourceSize: sourceSize).size
    }
    func show(_ image: NSImage, title: String, message: String? = nil,
              near switcherFrame: CGRect, sourceSize: CGSize) {
        let display = NSScreen.screens.max { left, right in
            let lhs = left.frame.intersection(switcherFrame)
            let rhs = right.frame.intersection(switcherFrame)
            return lhs.width * lhs.height < rhs.width * rhs.height
        } ?? NSScreen.main
        let visibleFrame = display?.visibleFrame ?? switcherFrame
        let contentFrame = FullSizePreviewLayout.frame(visibleFrame: visibleFrame,
                                                       sourceSize: sourceSize)
        let content = LargePreviewContent(image: image, message: message)
        if let panel, let hostingController {
            hostingController.rootView = content
            panel.title = "Large Preview — \(title)"
            if lastSourceSize != sourceSize || lastVisibleFrame != visibleFrame {
                panel.setFrame(panel.frameRect(forContentRect: contentFrame), display: true)
            }
            lastSourceSize = sourceSize
            lastVisibleFrame = visibleFrame
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(contentRect: contentFrame,
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = []
        hostingController.view.autoresizingMask = [.width, .height]
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.title = "Large Preview — \(title)"
        panel.contentViewController = hostingController
        panel.setFrame(panel.frameRect(forContentRect: contentFrame), display: true)
        panel.level = .statusBar
        self.panel = panel
        self.hostingController = hostingController
        lastSourceSize = sourceSize
        lastVisibleFrame = visibleFrame
        panel.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil); panel = nil; hostingController = nil; lastSourceSize = nil; lastVisibleFrame = nil }
    func windowWillClose(_ notification: Notification) {
        panel = nil; hostingController = nil; lastSourceSize = nil; lastVisibleFrame = nil; onClose?()
    }
}

struct FullSizePreviewLayout {
    static func frame(visibleFrame: CGRect, sourceSize: CGSize) -> CGRect {
        let availableWidth = max(1, visibleFrame.width - 64)
        let availableHeight = max(1, visibleFrame.height - 96)
        let aspect = sourceSize.width > 0 && sourceSize.height > 0
            ? sourceSize.width / sourceSize.height : 16.0 / 10.0
        let width = min(availableWidth, availableHeight * aspect)
        let height = width / aspect
        return CGRect(x: visibleFrame.midX - width / 2,
                      y: visibleFrame.midY - height / 2,
                      width: width, height: height)
    }
}

private struct LargePreviewContent: View {
    let image: NSImage
    let message: String?
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Selected window preview")
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }.padding(18)
    }
}
