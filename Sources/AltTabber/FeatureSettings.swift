import Foundation

enum LargePreviewTrigger: String, Codable, CaseIterable, Identifiable {
    case section
    case control
    case either

    var id: Self { self }
    var title: String {
        switch self {
        case .section: "§ key"
        case .control: "Control key"
        case .either: "§ or Control"
        }
    }
    var usesSection: Bool { self == .section || self == .either }
    var usesControl: Bool { self == .control || self == .either }
}

// Codable defaults permit older backups to omit newly introduced preferences.
struct FeatureSettings: Codable, Equatable {
    var schemaVersion = 1
    var switcherStyle = SurfaceAppearance()
    var dockStyle = SurfaceAppearance()
    var commandTabStyle = SurfaceAppearance()
    var switcherEnabled = true
    var commitOnRelease = true
    var instantSwitcher = true
    var startOnSecond = true
    var passArrowsThrough = false
    var alternateActiveAppOnly = true
    var commandTabForwardKey = 0
    var commandTabBackwardKey = 50
    var closeKeyAction = WindowAction.close
    var minimizeKeyAction = WindowAction.minimize
    var quitKeyAction = WindowAction.quit
    var showSmallWindows = false
    var openNewWindowForWindowless = false
    var quitAfterLastWindowClosed = false
    var dockSortOrder = WindowSortOrder.recent
    var commandTabSortOrder = WindowSortOrder.recent
    var dockBuffer = 12.0
    var dockOnlyInitialDelay = false
    var anchorDockPreview = true
    var keepPreviewAfterFocus = true
    var keepPreviewOnTerminate = false
    var preventDockHide = false
    var fadeDuration = 0.0
    var titleBarWidthScale = 0.8
    var titleBarHeightScale = 0.8
    var titleBarRestoreInterval = 1.5
    var dockLockModifier = ShortcutModifier.option
    var globalSwipeVertical = false
    var indicatorHex = "007AFF"
    var indicatorHeight = 4.0
    var indicatorLength = 40.0
    var indicatorOffset = 5.0
    var indicatorShift = 0.0
    var indicatorAutoSize = true
    var showMassActions = true
    var disableImages = false
    var mediaScrollSeek = true
    var searchEnabled = true
    var searchFuzziness = 3
    var vimNavigation = false
    var hoverSelection = false
    var hoverScrollDuration = 0.12
    var includeHidden = false
    var showWindowlessApps = false
    var activeAppOnly = false
    var currentSpaceOnly = false
    var currentDisplayOnly = false
    var minimizedLast = false
    var sortOrder = WindowSortOrder.recent
    var excludedApps = ""
    var excludedTitles = ""
    var fullscreenBlacklist = ""
    var groupedApps = ""
    var collapseNativeTabs = false
    var dockEnabled = false
    var customDockEnabled = false
    var customDockEdge = CustomDockEdge.bottom
    var customDockIconSize = 48.0
    var customDockShowOnAllDisplays = false
    var customDockHoverPreviews = true
    var customDockActiveClickHides = false
    var customDockAppSenseEnabled = false
    var dockProfiles = [CustomDockProfile.initial]
    var activeDockProfileID = CustomDockProfile.initial.id
    var displayDockProfiles: [String: String] = [:]
    var customDockFileTrayEnabled = false
    var customDockStagedFiles: [String] = []
    var dockCurrentSpaceOnly = false
    var dockCurrentDisplayOnly = false
    var dockIncludeHidden = true
    var dockShowWindowless = true
    var dockIgnoreSingleWindow = false
    var dockGroupInstances = true
    var dockActivation = DockActivation.hover
    var dockModifier = ShortcutModifier.option
    var dockOpenDelay = 0.2
    var dockDismissDelay = 0.25
    var dockHoverFocus = false
    var dockHoverFocusDelay = 1.0
    var dockClickHide = false
    var dockRestoreMinimized = false
    var dockQuickQuit = false
    var dockScroll = false
    var cmdTabEnabled = false
    var cmdTabAutoSelect = false
    var cmdTabCurrentSpaceOnly = false
    var cmdTabCurrentDisplayOnly = false
    var cmdTabIncludeHidden = true
    var cmdTabShowWindowless = false
    var cmdTabIgnoreSingleWindow = false
    var compactThreshold = 0
    var dockCompactThreshold = 0
    var cmdTabCompactThreshold = 0
    var showControls = true
    var showBadges = true
    var showAppHeader = true
    var cornerRadius = 12.0
    var spacing = 12.0
    var backgroundOpacity = 1.0
    var material = PreviewMaterial.frosted
    var reducedMotion = false
    var previewWidth = 0.0
    var previewHeight = 0.0
    var keepAspectRatio = true
    var liveDock = false
    var liveSwitcher = false
    var liveFrameRate = 10
    var dockLiveFrameRate = 24
    var dockLiveScale = 1.0
    var liveScale = 0.5
    var liveSelectedAppOnly = true
    var liveKeepAlive = 0.0
    var cacheSeconds = 600.0
    var captureScale = 1.0
    var placement = PanelPlacement.pointer
    var pinnedDisplay = ""
    var horizontalOffset = 0.0
    var verticalOffset = 0.0
    var anchorTop = false
    var mouseFollowsFocus = false
    var previewGestures = false
    var globalSwipe = false
    var swipeFingers = 3
    var swipeThreshold = 50.0
    var middleClickAction = WindowAction.close
    var swipeUpAction = WindowAction.maximize
    var swipeDownAction = WindowAction.minimize
    var titleBarScroll = false
    var shakeMinimizeOthers = false
    var dockLock = false
    var dockLockDisplay = ""
    var indicator = false
    var indicatorStyle = IndicatorStyle.bar
    var foldersEnabled = false
    var folderShowHidden = false
    var folderSort = FolderSort.modified
    var folderDescending = true
    var folderRememberSort = true
    var calendarEnabled = false
    var calendarExclusions = ""
    var mediaEnabled = false
    var widgetExclusions = ""
    var embeddedWidgets = true
    var pinWidgets = true
    var lyricsEnabled = false
    var updatesEnabled = false
    var updateChannel = UpdateChannel.stable
    var showMenuBarIcon = true
    var debugLogging = false
    var primaryShortcut = Shortcut(keyCode: 48, modifier: .option)
    var alternateShortcut = Shortcut(keyCode: 0, modifier: .control, enabled: false)
    var selectionKey = 36
    var backwardKey = 48
    var searchKey = 44
    var closeKey = 13
    var minimizeKey = 46
    var quitKey = 12
    var largePreviewKey = 35
    var largePreviewTrigger = LargePreviewTrigger.section
    var persistedOrder: [String] = []
    var authorizedFolders: [String: Data] = [:]
    var folderSorts: [String: FolderSort] = [:]
    var onboardingCompleted = false

    mutating func normalize() {
        if dockProfiles.isEmpty { dockProfiles = [.initial] }
        var profileIDs = Set<String>()
        dockProfiles = dockProfiles.filter { !$0.id.isEmpty && profileIDs.insert($0.id).inserted }
        if dockProfiles.isEmpty { dockProfiles = [.initial] }
        if !dockProfiles.contains(where: { $0.id == activeDockProfileID }) { activeDockProfileID = dockProfiles[0].id }
        displayDockProfiles = displayDockProfiles.filter { _, id in dockProfiles.contains { $0.id == id } }
        customDockIconSize = min(96, max(28, customDockIconSize))
        customDockStagedFiles = Array(NSOrderedSet(array: customDockStagedFiles).compactMap { $0 as? String }.prefix(100))
        switcherStyle.normalize(); dockStyle.normalize(); commandTabStyle.normalize()
        dockBuffer = min(100, max(-40, dockBuffer))
        fadeDuration = min(2, max(0, fadeDuration))
        titleBarWidthScale = min(1, max(0.2, titleBarWidthScale))
        titleBarHeightScale = min(1, max(0.2, titleBarHeightScale))
        indicatorLength = min(150, max(4, indicatorLength))
        indicatorHeight = min(20, max(1, indicatorHeight))
        primaryShortcut.keyCode = min(127, max(0, primaryShortcut.keyCode))
        alternateShortcut.keyCode = min(127, max(0, alternateShortcut.keyCode))
        largePreviewKey = min(127, max(0, largePreviewKey))
        searchFuzziness = min(5, max(1, searchFuzziness))
        hoverScrollDuration = min(0.5, max(0, hoverScrollDuration))
        dockOpenDelay = min(5, max(0, dockOpenDelay))
        dockDismissDelay = min(5, max(0.1, dockDismissDelay))
        liveFrameRate = min(30, max(1, liveFrameRate))
        dockLiveFrameRate = min(30, max(1, dockLiveFrameRate))
        liveScale = min(1, max(0.1, liveScale))
        dockLiveScale = min(1, max(0.1, dockLiveScale))
        cacheSeconds = min(3600, max(0, cacheSeconds))
        liveKeepAlive = min(30, max(0, liveKeepAlive))
        cornerRadius = min(40, max(0, cornerRadius))
        spacing = min(40, max(0, spacing))
        backgroundOpacity = min(1, max(0.1, backgroundOpacity))
        captureScale = min(2, max(0.25, captureScale))
        previewWidth = min(900, max(0, previewWidth))
        previewHeight = min(600, max(0, previewHeight))
        swipeFingers = min(4, max(3, swipeFingers))
        swipeThreshold = min(500, max(10, swipeThreshold))
        horizontalOffset = min(45, max(-45, horizontalOffset))
        verticalOffset = min(45, max(-45, verticalOffset))
    }

    var shortcutConflicts: [String] {
        var conflicts: [String] = []
        if alternateShortcut.enabled && primaryShortcut.enabled
            && primaryShortcut.keyCode == alternateShortcut.keyCode
            && primaryShortcut.modifier == alternateShortcut.modifier {
            conflicts.append("Primary and alternate shortcuts are identical.")
        }
        if backwardKey != primaryShortcut.keyCode && backwardKey == selectionKey {
            conflicts.append("Backward and selection keys are identical.")
        }
        if largePreviewTrigger.usesSection && selectionKey == 10 {
            conflicts.append("§ cannot both select a window and open the large preview.")
        }
        if largePreviewTrigger.usesSection && searchKey == 10 {
            conflicts.append("§ cannot both start search and open the large preview.")
        }
        if largePreviewTrigger.usesSection && primaryShortcut.modifier == .option
            && (primaryShortcut.keyCode == 10 || backwardKey == 10) {
            conflicts.append("§ large preview conflicts with a switcher shortcut.")
        }
        if (primaryShortcut.enabled && primaryShortcut.modifier == .command
            && (primaryShortcut.keyCode == largePreviewKey || backwardKey == largePreviewKey))
            || (alternateShortcut.enabled && alternateShortcut.modifier == .command
            && alternateShortcut.keyCode == largePreviewKey) {
            conflicts.append("Large preview conflicts with a switcher shortcut.")
        }
        let actions = [(closeKey, "Close"), (minimizeKey, "Minimize"), (quitKey, "Quit"),
                       (largePreviewKey, "Large preview")]
        for left in actions.indices {
            for right in actions.indices where right > left && actions[left].0 == actions[right].0 {
                conflicts.append("\(actions[left].1) and \(actions[right].1) use the same Command key.")
            }
        }
        return conflicts
    }

    static func decode(_ data: Data) throws -> Self {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let supplied = object as? [String: Any] else { throw SettingsBackupError.invalidFormat }
        let encodedDefaults = try JSONEncoder().encode(Self())
        var merged = try JSONSerialization.jsonObject(with: encodedDefaults) as! [String: Any]
        func merge(_ original: [String: Any], _ incoming: [String: Any]) -> [String: Any] {
            var result = original
            for (key, value) in incoming {
                if let nested = value as? [String: Any], let defaults = original[key] as? [String: Any] { result[key] = merge(defaults, nested) }
                else { result[key] = value }
            }
            return result
        }
        merged = merge(merged, supplied)
        var result = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: merged))
        guard result.schemaVersion == 1 else { throw SettingsBackupError.unsupportedVersion }
        result.normalize()
        return result
    }
}

enum WindowSortOrder: String, Codable, CaseIterable { case recent, title, application, oldest, persistent }
enum DockActivation: String, Codable, CaseIterable { case hover, middleClick, modifierClick }
enum PreviewMaterial: String, Codable, CaseIterable { case frosted, clear, glass }
enum PanelPlacement: String, Codable, CaseIterable { case pointer, activeWindow, main, pinned }
enum IndicatorStyle: String, Codable, CaseIterable { case bar, dots, count }
enum FolderSort: String, Codable, CaseIterable { case name, modified, created, kind, size }
enum UpdateChannel: String, Codable, CaseIterable { case stable, nightly }
enum ShortcutModifier: String, Codable, CaseIterable { case option, control, command }
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifier: ShortcutModifier
    var enabled = true
}
enum SettingsBackupError: Error, LocalizedError {
    case invalidFormat, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "This file is not an AltTabber settings backup."
        case .unsupportedVersion: "This backup requires a newer version of AltTabber."
        }
    }
}
