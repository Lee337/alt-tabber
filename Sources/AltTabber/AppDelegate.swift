import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SwitcherModel()
    private let settings = AppSettings()
    private let windowService = WindowService()
    private let shortcutMonitor = GlobalShortcutMonitor()
    private lazy var panelController = SwitcherPanelController(model: model, settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        onRequestAccessibility: { [weak self] in self?.requestAccessibility() },
        onRequestScreenRecording: { [weak self] in self?.requestScreenRecording() }
    )
    private var statusItem: NSStatusItem?
    private weak var launchAtLoginMenuItem: NSMenuItem?
    private weak var shortcutStatusMenuItem: NSMenuItem?
    private weak var previewStatusMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()
    private var thumbnailTask: Task<Void, Never>?
    private var shortcutRecoveryTask: Task<Void, Never>?
    private var switchOriginWindowID: CGWindowID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureModel()
        configureStatusItem()
        updatePreviewStatus(
            PermissionManager.hasScreenRecordingAccess ? .checking : .permissionRequired
        )
        startShortcutMonitor(promptIfNeeded: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        thumbnailTask?.cancel()
        shortcutRecoveryTask?.cancel()
        shortcutMonitor.stop()
    }

    private func configureModel() {
        model.onCommit = { [weak self] item in
            guard let self else { return }
            thumbnailTask?.cancel()
            thumbnailTask = nil
            panelController.hide()
            let originWindowID = switchOriginWindowID
            switchOriginWindowID = nil
            if windowService.focus(item) {
                var invalidatedWindowIDs: Set<CGWindowID> = [item.id]
                if let originWindowID {
                    invalidatedWindowIDs.insert(originWindowID)
                }
                windowService.invalidateThumbnails(for: invalidatedWindowIDs)
            }
        }
        model.onCancel = { [weak self] in
            self?.panelController.hide()
            self?.switchOriginWindowID = nil
        }

        shortcutMonitor.onCycle = { [weak self] backwards in
            self?.cycle(backwards: backwards)
        }
        shortcutMonitor.onCommit = { [weak self] in
            self?.model.commit()
        }
        shortcutMonitor.onCancel = { [weak self] in
            self?.model.cancel()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "AltTabber"
        )

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Window Switcher", action: #selector(showFromMenu), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let shortcutStatusItem = NSMenuItem(title: "Shortcut: Checking…", action: nil, keyEquivalent: "")
        shortcutStatusItem.isEnabled = false
        menu.addItem(shortcutStatusItem)
        shortcutStatusMenuItem = shortcutStatusItem

        let previewStatusItem = NSMenuItem(title: "Previews: Checking…", action: nil, keyEquivalent: "")
        previewStatusItem.isEnabled = false
        menu.addItem(previewStatusItem)
        previewStatusMenuItem = previewStatusItem
        menu.addItem(.separator())

        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(requestAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let recordingItem = NSMenuItem(title: "Grant Screen Recording Access…", action: #selector(requestScreenRecording), keyEquivalent: "")
        recordingItem.target = self
        menu.addItem(recordingItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginMenuItem = loginItem
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit AltTabber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item

        settings.$launchAtLogin
            .sink { [weak self] enabled in
                self?.launchAtLoginMenuItem?.state = enabled ? .on : .off
            }
            .store(in: &cancellables)
    }

    private func startShortcutMonitor(promptIfNeeded: Bool) {
        if !PermissionManager.hasAccessibilityAccess, promptIfNeeded {
            PermissionManager.requestAccessibilityAccessOnce()
        }

        if !attemptToStartShortcut() {
            scheduleShortcutRecovery()
        }
    }

    @discardableResult
    private func attemptToStartShortcut() -> Bool {
        let started = shortcutMonitor.start()
        updateShortcutStatus(started ? .ready : .unavailable)
        if started {
            shortcutRecoveryTask?.cancel()
            shortcutRecoveryTask = nil
        }
        return started
    }

    private func scheduleShortcutRecovery() {
        guard shortcutRecoveryTask == nil else { return }
        shortcutRecoveryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.attemptToStartShortcut() { return }
            }
        }
    }

    private func updateShortcutStatus(_ status: ShortcutStatus) {
        settings.setShortcutStatus(status)
        shortcutStatusMenuItem?.title = "Shortcut: \(status.title)"
        statusItem?.button?.contentTintColor = status == .ready ? nil : .systemOrange
    }

    private func updatePreviewStatus(_ status: PreviewStatus) {
        settings.setPreviewStatus(status)
        previewStatusMenuItem?.title = "Previews: \(status.title)"
    }

    private func cycle(backwards: Bool) {
        if !panelController.isVisible {
            presentSwitcher()
        }
        model.cycle(backwards: backwards)
    }

    private func presentSwitcher() {
        let windows = windowService.visibleWindows()
        switchOriginWindowID = windows.first?.id
        model.replaceWindows(windows)
        panelController.show()
        loadThumbnails(for: windows)
    }

    private func loadThumbnails(for windows: [WindowItem]) {
        thumbnailTask?.cancel()
        guard PermissionManager.hasScreenRecordingAccess else {
            updatePreviewStatus(.permissionRequired)
            return
        }
        updatePreviewStatus(.checking)
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let result = await windowService.loadThumbnails(for: windows)
            guard !Task.isCancelled else { return }
            for (windowID, title) in result.titles {
                model.setTitle(title, for: windowID)
            }
            for (windowID, image) in result.images {
                model.setThumbnail(image, for: windowID)
            }

            if !result.images.isEmpty {
                updatePreviewStatus(.ready(result.images.count))
            } else if !PermissionManager.hasScreenRecordingAccess {
                updatePreviewStatus(.permissionRequired)
            } else if let failureDescription = result.failureDescription {
                updatePreviewStatus(.unavailable(failureDescription))
            } else {
                updatePreviewStatus(.unavailable("no matching windows"))
            }
        }
    }

    @objc private func showFromMenu() {
        presentSwitcher()
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func requestAccessibility() {
        PermissionManager.requestAccessibilityAccess()
        startShortcutMonitor(promptIfNeeded: false)
    }

    @objc private func requestScreenRecording() {
        if PermissionManager.requestScreenRecordingAccess()
            || PermissionManager.hasScreenRecordingAccess {
            updatePreviewStatus(.checking)
        } else {
            updatePreviewStatus(.permissionRequired)
            PermissionManager.openScreenRecordingSettings()
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            try settings.setLaunchAtLogin(!settings.launchAtLogin)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t update Launch at Login"
            alert.runModal()
        }
    }
}
