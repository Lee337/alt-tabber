import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(
        settings: AppSettings,
        onRequestAccessibility: @escaping () -> Void,
        onRequestScreenRecording: @escaping () -> Void
    ) {
        let rootView = SettingsView(
            settings: settings,
            onRequestAccessibility: onRequestAccessibility,
            onRequestScreenRecording: onRequestScreenRecording
        )
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1000, height: 800)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: min(840, available.width - 40), height: min(650, available.height - 60)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AltTabber Settings"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
