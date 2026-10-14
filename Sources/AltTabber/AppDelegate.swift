import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ScriptingDelegate {
    private let model = SwitcherModel()
    private let settings = AppSettings()
    private let windowService = WindowService()
    private lazy var actions = WindowActionService(windows: windowService)
    private let inputMonitor = OverlayInputMonitor()
    private let dockIntegration = DockIntegration()
    private let customDock = CustomDockController()
    private let livePreviews = LivePreviewService()
    private let widgetPanels = WidgetPanelController()
    private let dockAutoHide = DockAutoHideLease()
    private var showTask: Task<Void, Never>?
    private var customDockDismissTask: Task<Void, Never>?
    private var presentationActive = false
    private var commandTabSelectionMade = false
    private let updater = UpdateService()
    private let indicator = ActiveAppIndicator()
    private let globalSwipe = GlobalSwipeService()
    private let titleBarScroll = TitleBarScrollService()
    private let peekPanel = FullSizePreviewController()
    private var largePreviewRequested = false
    private var largePreviewCaptureTask: Task<Void, Never>?
    private var largePreviewCaptureWindowID: CGWindowID?
    private var largePreviewImage: (windowID: CGWindowID, image: NSImage)?
    private var presentationID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var settingsChangeTask: Task<Void, Never>?
    private var gestureTravel = 0.0
    private var gestureFired = false
    private var shakeDetector = ShakeDetector()
    private var liveTask: Task<Void, Never>?
    private var localInputToken: Any?
    private var observationTokens: [NSObjectProtocol] = []
    private var scopedBundleIdentifier: String?
    private var scopedProcessID: pid_t?
    private let shortcutMonitor = GlobalShortcutMonitor()
    private lazy var panelController = SwitcherPanelController(model: model, settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        onRequestAccessibility: { [weak self] in self?.requestAccessibility() },
        onRequestScreenRecording: { [weak self] in self?.requestScreenRecording() }
    )
    private var statusItem: NSStatusItem?
    private weak var launchAtLoginMenuItem: NSMenuItem?
    private weak var accessibilityMenuItem: NSMenuItem?
    private weak var shortcutStatusMenuItem: NSMenuItem?
    private weak var previewStatusMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()
    private var thumbnailTask: Task<Void, Never>?
    private var shortcutRecoveryTask: Task<Void, Never>?
    private var switchOriginWindowID: CGWindowID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureModel()
        configureStatusItem()
        configureApplicationMenu()
        updatePreviewStatus(
            PermissionManager.hasScreenRecordingAccess ? .checking : .permissionRequired
        )
        configureFeatures()
        startShortcutMonitor(promptIfNeeded: true)
        if !settings.features.onboardingCompleted { settingsWindowController.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController.show(); return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        thumbnailTask?.cancel()
        shortcutRecoveryTask?.cancel()
        showTask?.cancel()
        customDockDismissTask?.cancel()
        dockAutoHide.release()
        refreshTask?.cancel()
        settingsChangeTask?.cancel()
        liveTask?.cancel()
        inputMonitor.stop()
        if let localInputToken { NSEvent.removeMonitor(localInputToken) }
        localInputToken = nil
        globalSwipe.stop()
        dockIntegration.stop()
        customDock.stop()
        livePreviews.stop()
        widgetPanels.closeAll()
        for token in observationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        shortcutMonitor.stop()
    }

    private func configureModel() {
        peekPanel.onClose = { [weak self] in
            self?.largePreviewRequested = false
            self?.largePreviewCaptureTask?.cancel()
            self?.largePreviewCaptureTask = nil
            self?.largePreviewCaptureWindowID = nil
            self?.largePreviewImage = nil
        }
        model.onEntryCommit = { [weak self] entry in
            guard let self else { return }
            hidePresentation()
            let result = actions.perform(entry.window == nil && settings.features.openNewWindowForWindowless ? .newWindow : .focus, on: entry)
            if let item = entry.window, result == .success {
                windowService.markUsed(item)
                windowService.invalidateThumbnails(for: Set([item.id, switchOriginWindowID].compactMap { $0 }))
                if settings.features.mouseFollowsFocus {
                    CGWarpMouseCursorPosition(CGPoint(x: item.bounds.midX, y: item.bounds.midY))
                }
            }
            switchOriginWindowID = nil
        }
        model.onCancel = { [weak self] in self?.hidePresentation() }
        model.onAction = { [weak self] action, entry in
            guard let self else { return }
            let result = actions.perform(action, on: entry)
            DiagnosticLog.shared.record("Action \(action.rawValue): \(result.rawValue)")
            model.actionMessage = result == .success ? nil : "\(action.title): \(result.rawValue)"
            if result == .success {
                if action == .focus && model.surface == .dock && !settings.features.keepPreviewAfterFocus { hidePresentation() }
                if action == .close && settings.features.quitAfterLastWindowClosed {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard let self, !windowService.entries().contains(where: { $0.processID == entry.processID && $0.window != nil }) else { return }
                        _ = actions.perform(.quit, on: entry)
                    }
                }
                refreshPresentation()
            }
        }
        model.isActionAvailable = { [weak self] action, entry in self?.actions.available(action, for: entry) ?? false }
        model.onUserSelection = { [weak self] in
            guard let self, model.surface == .commandTab else { return }; commandTabSelectionMade = true
        }
        model.onVisibleEntriesChanged = { [weak self] in self?.updateLivePreviews() }
        model.onSelectionChanged = { [weak self] in
            self?.updateLivePreviews()
            self?.updateLargePreview()
        }
        model.onLargePreview = { [weak self] in self?.toggleLargePreview() }

        shortcutMonitor.onCycle = { [weak self] backwards in
            self?.cycle(backwards: backwards)
        }
        shortcutMonitor.onAlternate = { [weak self] in
            guard let self else { return }
            presentSwitcher(activeAppOnly: settings.features.alternateActiveAppOnly)
            model.releaseHint = "Press Return to switch"
        }
        shortcutMonitor.onCommit = { [weak self] in
            guard let self else { return }
            if settings.features.commitOnRelease { model.commit() } else { model.releaseHint = "Press Return to switch" }
        }
        shortcutMonitor.onCancel = { [weak self] in
            self?.model.cancel()
        }
        shortcutMonitor.onPreviewKey = { [weak self] in
            guard let self, presentationActive else { return }
            if model.searchText.isEmpty { toggleLargePreview() }
            else { model.searchText += "§" }
        }
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem(); main.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "AltTabber")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AltTabber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; applicationMenu.addItem(quit); applicationItem.submenu = applicationMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = edit; NSApp.mainMenu = main
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "AltTabber"
        )

        let menu = NSMenu()
        let versionItem = NSMenuItem(title: versionMenuTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

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
        accessibilityMenuItem = accessibilityItem
        updateAccessibilityMenuItem()

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

    private var versionMenuTitle: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "AltTabber \(version) (\(build))"
        }
        return "AltTabber \(version)"
    }

    private func startShortcutMonitor(promptIfNeeded: Bool) {
        guard settings.features.switcherEnabled else {
            shortcutMonitor.stop(); shortcutRecoveryTask?.cancel(); shortcutRecoveryTask = nil
            updateShortcutStatus(.disabled); return
        }
        if !PermissionManager.hasAccessibilityAccess, promptIfNeeded {
            PermissionManager.requestAccessibilityAccessOnce()
        }

        if !attemptToStartShortcut() {
            scheduleShortcutRecovery()
        }
    }

    @discardableResult
    private func attemptToStartShortcut() -> Bool {
        if settings.features.cmdTabEnabled && settings.features.primaryShortcut == Shortcut(keyCode: 48, modifier: .command) {
            updateShortcutStatus(.unavailable); return false
        }
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

    private func updateAccessibilityMenuItem() {
        let granted = PermissionManager.hasAccessibilityAccess
        accessibilityMenuItem?.title = granted
            ? "Accessibility: Granted"
            : "Grant Accessibility Access…"
        accessibilityMenuItem?.isEnabled = !granted
    }

    private func cycle(backwards: Bool) {
        if !presentationActive {
            presentSwitcher()
            if !settings.features.startOnSecond { return }
        }
        model.cycle(backwards: backwards)
    }

    private func presentSwitcher(activeAppOnly: Bool = false) {
        guard settings.features.switcherEnabled else { return }
        guard !(windowService.frontmostIsFullscreen && WindowQuery.tokens(settings.features.fullscreenBlacklist).contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")) else { return }
        widgetPanels.hide()
        panelController.embed()
        model.surface = .switcher
        scopedBundleIdentifier = nil
        scopedProcessID = activeAppOnly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        model.searchText = ""
        model.settings = settings.features
        model.releaseHint = "Release \(settings.features.primaryShortcut.modifier == .option ? "⌥" : settings.features.primaryShortcut.modifier == .command ? "⌘" : "⌃") to switch"
        presentationID = UUID()
        model.replaceEntries(queryEntries())
        presentationActive = true
        switchOriginWindowID = model.windows.first?.id
        showTask?.cancel()
        if settings.features.instantSwitcher { panelController.show(); beginPresentationUpdates() }
        else {
            let session = presentationID
            showTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled, presentationActive, session == presentationID else { return }
                panelController.show(near: dockIntegration.commandTabFrame); beginPresentationUpdates()
                if largePreviewRequested { updateLargePreview() }
            }
        }
    }

    private func queryEntries() -> [SelectionEntry] {
        let display = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
        let query = WindowQuery(surface: model.surface, processID: scopedProcessID,
            currentAppID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            displayID: display, currentSpaces: PlatformCapabilities.shared.currentSpaces())
        let started = Date()
        let entries = windowService.entries().filter { scopedBundleIdentifier == nil || $0.bundleIdentifier == scopedBundleIdentifier }
        DiagnosticLog.shared.record("Window discovery: \(entries.count) entries in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        return query.apply(to: entries, settings: settings.features)
    }

    private func hidePresentation() {
        presentationActive = false
        customDockDismissTask?.cancel(); customDockDismissTask = nil
        showTask?.cancel(); showTask = nil
        dockAutoHide.release()
        presentationID = UUID()
        refreshTask?.cancel(); refreshTask = nil
        thumbnailTask?.cancel(); thumbnailTask = nil
        liveTask?.cancel(); liveTask = nil
        shortcutMonitor.endSession()
        panelController.hide()
        largePreviewRequested = false
        largePreviewCaptureTask?.cancel(); largePreviewCaptureTask = nil
        largePreviewCaptureWindowID = nil; largePreviewImage = nil
        peekPanel.hide()
        livePreviews.stop(after: settings.features.liveKeepAlive)
    }

    private func toggleLargePreview() {
        guard presentationActive else { return }
        if largePreviewRequested {
            largePreviewRequested = false
            largePreviewCaptureTask?.cancel(); largePreviewCaptureTask = nil
            largePreviewCaptureWindowID = nil; largePreviewImage = nil
            peekPanel.hide()
        } else {
            largePreviewRequested = true
            updateLargePreview()
        }
    }

    private func updateLargePreview(message overrideMessage: String? = nil) {
        guard largePreviewRequested, panelController.isVisible else { return }
        guard let entry = model.selectedEntry else {
            largePreviewCaptureTask?.cancel(); largePreviewCaptureTask = nil
            largePreviewCaptureWindowID = nil; largePreviewImage = nil
            peekPanel.hide(); return
        }
        let selectedWindow = entry.window
        if largePreviewCaptureWindowID != selectedWindow?.id {
            largePreviewCaptureTask?.cancel(); largePreviewCaptureTask = nil
            largePreviewCaptureWindowID = nil; largePreviewImage = nil
        }
        let sourceSize = selectedWindow?.bounds.size ?? CGSize(width: 4, height: 3)
        let largeImage = selectedWindow.flatMap { window in
            largePreviewImage?.windowID == window.id ? largePreviewImage?.image : nil
        }
        if let image = largeImage ?? selectedWindow?.thumbnail {
            peekPanel.show(image, title: entry.title, near: panelController.frame, sourceSize: sourceSize)
        } else {
            let explanation: String
            if selectedWindow == nil { explanation = "This app has no open window."
            } else if settings.features.disableImages { explanation = "Window images are disabled in Capture settings."
            } else if !PermissionManager.hasScreenRecordingAccess { explanation = "Screen Recording access is required for a window image."
            } else { explanation = overrideMessage ?? "Loading window image…" }
            peekPanel.show(entry.icon, title: entry.title, message: explanation,
                           near: panelController.frame, sourceSize: sourceSize)
        }
        guard let window = selectedWindow, !settings.features.disableImages,
              PermissionManager.hasScreenRecordingAccess,
              largePreviewCaptureWindowID != window.id else { return }
        largePreviewCaptureTask?.cancel()
        largePreviewImage = nil
        largePreviewCaptureWindowID = window.id
        let contentSize = peekPanel.contentSize(near: panelController.frame, sourceSize: sourceSize)
        let maximumPixelSize = CGSize(width: contentSize.width * 2, height: contentSize.height * 2)
        let session = presentationID
        largePreviewCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await windowService.captureLargePreview(for: window, maximumPixelSize: maximumPixelSize)
            guard !Task.isCancelled, session == presentationID, largePreviewRequested,
                  model.selectedWindow?.id == window.id, let image else { return }
            largePreviewImage = (window.id, image)
            updateLargePreview()
        }
    }

    private func beginPresentationUpdates() {
        loadThumbnails(for: model.windows)
        updateLivePreviews()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, panelController.isVisible else { return }
                refreshPresentation()
            }
        }
    }

    private func refreshPresentation() {
        guard panelController.isVisible else { return }
        model.settings = settings.features
        let thumbnails = Dictionary(model.sourceEntries.compactMap { $0.window }.compactMap { item in item.thumbnail.map { (item.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let fresh = queryEntries().map { entry -> SelectionEntry in
            guard var window = entry.window else { return entry }
            window.thumbnail = thumbnails[window.id]
            return .window(window)
        }
        if fresh.isEmpty && model.surface == .dock && !settings.features.keepPreviewOnTerminate { hidePresentation(); return }
        model.replaceEntries(fresh, preserveSelection: true)
        loadThumbnails(for: model.windows)
    }

    private func updateLivePreviews() {
        guard panelController.isVisible else { return }
        let enabled = model.surface == .dock ? settings.features.liveDock : settings.features.liveSwitcher
        guard enabled else { livePreviews.stop(); return }
        guard !settings.features.disableImages else { livePreviews.stop(); return }
        let visible = panelController.visibleWindows
        let all = visible.isEmpty ? Array(model.windows.prefix(12)) : visible
        let windows = settings.features.liveSelectedAppOnly ? all.filter { $0.processID == model.selectedEntry?.processID } : all
        liveTask?.cancel()
        var streamSettings = settings.features
        if model.surface == .dock { streamSettings.liveFrameRate = settings.features.dockLiveFrameRate; streamSettings.liveScale = settings.features.dockLiveScale }
        liveTask = Task { [weak self] in
            guard let self else { return }
            await livePreviews.update(windows: windows, settings: streamSettings)
        }
    }

    private func loadThumbnails(for windows: [WindowItem]) {
        thumbnailTask?.cancel()
        guard !settings.features.disableImages else { return }
        guard PermissionManager.hasScreenRecordingAccess else {
            updatePreviewStatus(.permissionRequired)
            return
        }
        updatePreviewStatus(.checking)
        let session = presentationID
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            let result = await windowService.loadThumbnails(for: windows)
            guard !Task.isCancelled, session == presentationID else { return }
            for (windowID, title) in result.titles {
                model.setTitle(title, for: windowID)
            }
            for (windowID, image) in result.images {
                model.setThumbnail(image, for: windowID)
                if largePreviewRequested && model.selectedWindow?.id == windowID { updateLargePreview() }
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
            if largePreviewRequested && model.selectedWindow?.thumbnail == nil {
                updateLargePreview(message: result.failureDescription ?? "Window image unavailable for this window.")
            }
        }
    }

    private func configureFeatures() {
        customDock.onPreview = { [weak self] item, frame in
            guard let self, let pid = item.processID else { return }
            self.customDockDismissTask?.cancel()
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let target = DockTarget(frame: WindowGeometry.accessibilityFrame(frame, desktopTop: top),
                                    processID: pid, url: item.location.map(URL.init(fileURLWithPath:)), name: item.title)
            self.showDockPreview(target)
        }
        customDock.onPreviewExit = { [weak self] in
            self?.customDockDismissTask?.cancel()
            self?.customDockDismissTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, !Task.isCancelled, self.model.surface == .dock else { return }
                    if !self.customDock.containsPointer && !self.panelController.containsPointer {
                        self.hidePresentation(); return
                    }
                }
            }
        }
        customDock.onAction = { [weak self] action, item in
            guard let self, let pid = item.processID,
                  let app = NSRunningApplication(processIdentifier: pid) else { return }
            let entry = SelectionEntry.application(ApplicationItem(processID: pid, name: item.title,
                bundleIdentifier: app.bundleIdentifier, icon: app.icon ?? NSImage()))
            _ = self.actions.perform(action, on: entry)
            self.customDock.refresh(settings: self.settings)
        }
        livePreviews.onImage = { [weak self] id, image in
            guard let self, panelController.isVisible else { return }
            model.setThumbnail(image, for: id)
        }
        livePreviews.onFailure = { [weak self] message in self?.model.actionMessage = message }
        globalSwipe.onIntent = { [weak self] intent in
            guard let self else { return }
            switch intent {
            case .open: presentSwitcher(); model.cycle(backwards: false)
            case .forward: model.cycle(backwards: false)
            case .backward: model.cycle(backwards: true)
            case .commit: model.commit()
            }
        }
        localInputToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panelController.isVisible, let cg = event.cgEvent else { return event }
            return self.handleInput(.keyDown, event: cg) ? nil : event
        }
        inputMonitor.onEvent = { [weak self] type, event in self?.handleInput(type, event: event) ?? false }
        dockIntegration.onPreview = { [weak self] target in self?.showDockPreview(target) }
        dockIntegration.onReposition = { [weak self] frame in
            guard let self, presentationActive, model.surface == .dock else { return }
            panelController.show(near: frame)
        }
        dockIntegration.onDismiss = { [weak self] in
            guard let self else { return }
            if model.surface == .dock && !customDock.containsPointer { hidePresentation() }
            widgetPanels.hide()
            dockAutoHide.release()
        }
        dockIntegration.isPointerInsidePreview = { [weak self] in
            guard let self else { return false }
            return panelController.containsPointer || widgetPanels.containsPointer || customDock.containsPointer
        }
        dockIntegration.onCommandTab = { [weak self] pid in
            guard let self else { return }
            if let pid {
                hidePresentation()
                panelController.embed()
                commandTabSelectionMade = false
                model.surface = .commandTab; model.searchText = ""; model.settings = settings.features
                model.releaseHint = "⌘ A / ⌘ ` to select a window"
                presentationActive = true
                scopedBundleIdentifier = nil
                scopedProcessID = pid
                model.replaceEntries(queryEntries())
                panelController.show(near: dockIntegration.commandTabFrame); beginPresentationUpdates()
            } else if model.surface == .commandTab {
                if settings.features.cmdTabAutoSelect || commandTabSelectionMade { model.commit() } else { hidePresentation() }
            }
        }
        dockIntegration.onIndicator = { [weak self] target in
            guard let self else { return }
            indicator.show(target, style: settings.features.indicatorStyle,
                count: target?.processID.map { pid in windowService.entries().filter { $0.processID == pid && $0.window != nil }.count } ?? 0, settings: settings.features)
        }
        settings.$features.dropFirst().sink { [weak self] _ in
            self?.settingsChangeTask?.cancel()
            self?.settingsChangeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                applyFeatures()
            }
        }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if PermissionManager.hasAccessibilityAccess && !inputMonitor.isRunning { _ = inputMonitor.start() }
                    refreshPresentation()
                    customDock.refresh(settings: settings)
                }
            })
        }
        for name in [Notification.Name.altTabberCheckUpdates, .altTabberSaveOrder, .altTabberImportDockApps] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] notification in
                guard let self else { return }
                if notification.name == .altTabberCheckUpdates { updater.check() }
                else if notification.name == .altTabberSaveOrder { settings.features.persistedOrder = windowService.entries().map(\.id) }
                else {
                    var profile = settings.features.selectedDockProfile
                    let count = profile.importApplications(dockIntegration.dockItems().compactMap(\.url))
                    settings.features.updateDockProfile(profile)
                    DiagnosticLog.shared.record("Imported \(count) system Dock apps into \(profile.name)")
                }
            }.store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: .altTabberShowSettings).sink { [weak self] _ in
            self?.settingsWindowController.show()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            guard let self else { return }
            self.customDock.refresh(settings: self.settings)
        }.store(in: &cancellables)
        applyFeatures()
        ScriptingBridge.shared.delegate = self
    }

    private func applyFeatures() {
        let features = settings.features
        updater.configure(features)
        DiagnosticLog.shared.enabled = features.debugLogging
        shortcutMonitor.stop()
        shortcutMonitor.shortcut = features.primaryShortcut
        shortcutMonitor.alternate = features.alternateShortcut
        shortcutMonitor.backwardKeyCode = features.backwardKey
        shortcutMonitor.previewKeyCode = features.largePreviewTrigger.usesSection && features.selectionKey != 10 ? 10 : nil
        startShortcutMonitor(promptIfNeeded: false)
        windowService.showSmallWindows = features.showSmallWindows
        windowService.cacheSeconds = features.cacheSeconds
        windowService.captureScale = features.captureScale
        globalSwipe.stop()
        if features.globalSwipe { globalSwipe.fingers = features.swipeFingers; globalSwipe.vertical = features.globalSwipeVertical; globalSwipe.start() }
        dockIntegration.settings = features; dockIntegration.start()
        customDock.refresh(settings: settings)
        statusItem?.isVisible = features.showMenuBarIcon
        if !features.indicator { indicator.hide() }
        if PermissionManager.hasAccessibilityAccess { _ = inputMonitor.start() }
        else { inputMonitor.stop() }
        if !features.mediaEnabled { UniversalMediaAdapter.shared.stop() }
        if !features.dockEnabled { widgetPanels.closeAll() }
        refreshPresentation()
    }

    private func showDockPreview(_ target: DockTarget) {
        hidePresentation()
        panelController.embed()
        if settings.features.preventDockHide { dockAutoHide.acquire() }
        let excluded = WindowQuery.tokens(settings.features.widgetExclusions).contains(target.name)
        if !excluded, settings.features.foldersEnabled, let url = target.url,
           (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, url.pathExtension != "app" {
            widgetPanels.show(FolderWidgetView(model: FolderWidgetModel(url: url, settings: settings)), title: target.name, near: target.frame, settings: settings)
            return
        }
        let hasWindows = target.processID.map { pid in windowService.entries().contains { $0.processID == pid && $0.window != nil } } ?? false
        var embeddedCalendar: CalendarWidgetModel?
        var embeddedMedia: MediaWidgetModel?
        if !excluded, settings.features.calendarEnabled, let pid = target.processID,
           NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.iCal" {
            let calendar = CalendarWidgetModel(settings: settings)
            if settings.features.embeddedWidgets && hasWindows { embeddedCalendar = calendar }
            else { widgetPanels.show(CalendarWidgetView(model: calendar), title: "Calendar", near: target.frame, settings: settings); return }
        }
        if !excluded, settings.features.mediaEnabled, let pid = target.processID,
           let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           (["com.apple.Music", "com.spotify.client"].contains(bundle) || UniversalMediaAdapter.shared.snapshot?.processID == pid) {
            let media = MediaWidgetModel(bundleIdentifier: bundle, settings: settings)
            if settings.features.embeddedWidgets && hasWindows { embeddedMedia = media }
            else { widgetPanels.show(MediaWidgetView(model: media, settings: settings), title: "Now Playing", near: target.frame, settings: settings); return }
        }
        guard let pid = target.processID else { return }
        widgetPanels.hide()
        model.surface = .dock; model.searchText = ""; model.settings = settings.features
        scopedBundleIdentifier = settings.features.dockGroupInstances ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
        scopedProcessID = scopedBundleIdentifier == nil ? pid : nil
        model.replaceEntries(queryEntries())
        if model.entries.isEmpty { return }
        presentationActive = true
        panelController.embed(calendar: embeddedCalendar, media: embeddedMedia)
        panelController.show(near: target.frame)
        beginPresentationUpdates()
    }

    private func handleInput(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .mouseMoved, settings.features.dockLock {
            let screens = NSScreen.screens
            if let index = screens.firstIndex(where: { String($0.displayID) == settings.features.dockLockDisplay }) {
                let top = screens.first?.frame.maxY ?? 0
                let frames = screens.map { WindowGeometry.accessibilityFrame($0.frame, desktopTop: top) }
                event.location = DockLockGeometry.constrained(event.location, screens: frames, lockedIndex: index,
                    orientation: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom",
                    override: CGEventSource.flagsState(.combinedSessionState).contains(settings.features.dockLockModifier == .option ? .maskAlternate : settings.features.dockLockModifier == .control ? .maskControl : .maskCommand))
            }
        }
        if type == .mouseMoved, settings.features.shakeMinimizeOthers, panelController.containsPointer,
           let entry = panelController.entryAtPointer(), shakeDetector.update(x: event.location.x, at: Date().timeIntervalSinceReferenceDate) {
            for other in windowService.entries() where other.id != entry.id && other.window?.isMinimized == false {
                _ = actions.perform(.minimize, on: other)
            }
            refreshPresentation()
        }
        if type == .scrollWheel, settings.features.previewGestures, panelController.containsPointer,
           let entry = panelController.entryAtPointer() {
            let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            if phase == 1 { gestureTravel = 0; gestureFired = false }
            if phase == 1 || phase == 2 {
                let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
                let axis: CGEventField = model.surface == .dock && orientation != "bottom" ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1
                gestureTravel += Double(event.getIntegerValueField(axis))
                if !gestureFired && abs(gestureTravel) >= settings.features.swipeThreshold {
                    gestureFired = true
                    var away = gestureTravel > 0
                    if model.surface == .dock && orientation == "left" { away.toggle() }
                    model.perform(away ? settings.features.swipeUpAction : settings.features.swipeDownAction, entry: entry)
                }
                return true
            }
        }
        if type == .scrollWheel, settings.features.titleBarScroll, titleBarScroll.handle(event, actions: actions, windows: windowService, settings: settings.features) { return true }
        if type == .flagsChanged, presentationActive, panelController.isVisible,
           model.surface == .switcher {
            return OverlayKeyRouter.handleModifier(event, model: model, settings: settings.features)
        }
        if type == .keyDown, panelController.isVisible {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if model.surface == .commandTab && key == 48 { return false }
            if model.surface == .commandTab && (key == settings.features.commandTabForwardKey || key == settings.features.commandTabBackwardKey) {
                model.cycle(backwards: key == settings.features.commandTabBackwardKey); return true
            }
            return OverlayKeyRouter.handle(event, model: model, settings: settings.features)
        }
        if type == .otherMouseDown {
            if settings.features.dockActivation == .middleClick, dockIntegration.activateByClick() { return true }
            if panelController.containsPointer, let entry = panelController.entryAtPointer() {
                model.perform(settings.features.middleClickAction, entry: entry); return true
            }
        }
        if type == .leftMouseDown, settings.features.dockActivation == .modifierClick {
            let modifier = settings.features.dockModifier
            let flag: CGEventFlags = modifier == .option ? .maskAlternate : modifier == .command ? .maskCommand : .maskControl
            if event.flags.contains(flag), dockIntegration.activateByClick() { return true }
        }
        if type == .rightMouseDown, settings.features.dockQuickQuit, event.flags.contains(.maskCommand),
           let pid = dockIntegration.targetAtPointer()?.processID, let app = NSRunningApplication(processIdentifier: pid) {
            if event.flags.contains(.maskAlternate) { _ = app.forceTerminate() } else { _ = app.terminate() }
            return true
        }
        if type == .scrollWheel, settings.features.dockScroll, let pid = dockIntegration.targetAtPointer()?.processID,
           let app = NSRunningApplication(processIdentifier: pid), event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 {
            if app.isActive { _ = app.hide() } else { _ = app.activate() }
            return true
        }
        if type == .leftMouseDown, settings.features.dockClickHide, let pid = dockIntegration.targetAtPointer()?.processID,
           let app = NSRunningApplication(processIdentifier: pid), app.isActive { _ = app.hide(); return true }
        if type == .leftMouseDown, settings.features.dockRestoreMinimized, let pid = dockIntegration.targetAtPointer()?.processID {
            for entry in windowService.entries() where entry.processID == pid && entry.window?.isMinimized == true { _ = actions.perform(.minimize, on: entry) }
        }
        return false
    }

    func executeCommand(_ name: String, arguments: [String: Any]) async throws -> String {
        func appMatches(_ entry: SelectionEntry) -> Bool {
            if let pid = arguments["pid"] as? Int { return entry.processID == pid }
            if let bundle = arguments["bundle"] as? String { return entry.bundleIdentifier == bundle }
            if let app = arguments["app"] as? String { return entry.appName.localizedCaseInsensitiveCompare(app) == .orderedSame }
            return true
        }
        let entries = windowService.entries().filter(appMatches)
        func target() throws -> SelectionEntry {
            if let id = arguments["window"] as? Int {
                guard id > 0, id <= Int(UInt32.max), let entry = entries.first(where: { $0.window?.id == UInt32(id) }) else { throw ScriptingError.targetNotFound }
                return entry
            }
            if arguments["window"] as? String == "active" || arguments["window"] == nil {
                if let id = windowService.focusedWindowID(), let entry = entries.first(where: { $0.window?.id == id }) { return entry }
            }
            throw ScriptingError.targetNotFound
        }
        switch name {
        case "help":
            return try ScriptJSON.encode(["show-switcher", "show-preview", "hide-preview", "list-windows", "list-apps", "active-window", "get-window", "window-action"])
        case "show-switcher": presentSwitcher(activeAppOnly: arguments["activeAppOnly"] as? Bool ?? false); model.releaseHint = "Press Return to switch"
        case "hide-preview": hidePresentation(); widgetPanels.hide()
        case "show-preview":
            guard let entry = entries.first else { throw ScriptingError.targetNotFound }
            var frame = dockIntegration.dockItems().first { $0.processID == entry.processID }?.frame
                ?? CGRect(x: NSEvent.mouseLocation.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - NSEvent.mouseLocation.y, width: 1, height: 1)
            if let supplied = arguments["frame"] as? [String: Double], let x = supplied["x"], let y = supplied["y"] {
                frame = CGRect(x: x, y: y, width: max(1, supplied["width"] ?? 1), height: max(1, supplied["height"] ?? 1))
            }
            showDockPreview(DockTarget(frame: frame, processID: entry.processID, url: nil, name: entry.appName))
        case "list-windows": return try ScriptJSON.encode(entries.compactMap { $0.window }.map(ScriptWindow.init))
        case "list-apps":
            let groups = Dictionary(grouping: entries, by: \.processID)
            let apps = groups.values.compactMap { values -> ScriptApp? in
                guard let first = values.first else { return nil }
                return ScriptApp(pid: first.processID, name: first.appName, bundleIdentifier: first.bundleIdentifier,
                    windowCount: values.filter { $0.window != nil }.count)
            }.sorted { $0.pid < $1.pid }
            return try ScriptJSON.encode(apps)
        case "active-window", "get-window":
            guard let window = try target().window else { throw ScriptingError.targetNotFound }
            var result = ScriptWindow(window)
            if arguments["image"] as? Bool == true {
                guard PermissionManager.hasScreenRecordingAccess else { throw ScriptingError.actionFailed(.permissionDenied) }
                let loaded = await windowService.loadThumbnails(for: [window])
                if let image = loaded.images.first?.1, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    result.previewPNG = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.base64EncodedString()
                }
            }
            return try ScriptJSON.encode(result)
        case "window-action":
            guard let actionName = arguments["action"] as? String, let action = WindowAction(rawValue: actionName) else { throw ScriptingError.invalidArguments }
            let result = actions.perform(action, on: try target())
            guard result == .success else { throw ScriptingError.actionFailed(result) }
            refreshPresentation()
        default: throw ScriptingError.unknownCommand
        }
        return "{\"result\":\"success\"}"
    }

    @objc private func showFromMenu() {
        presentSwitcher()
        model.releaseHint = "Press Return to switch"
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func requestAccessibility() {
        PermissionManager.requestAccessibilityAccess()
        updateAccessibilityMenuItem()
        applyFeatures()
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
