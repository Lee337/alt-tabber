import Foundation

struct BooleanSetting: Identifiable {
    let title: String
    let key: WritableKeyPath<FeatureSettings, Bool>
    var id: String { title }
}
struct NumberSetting: Identifiable {
    let title: String
    let key: WritableKeyPath<FeatureSettings, Double>
    let range: ClosedRange<Double>
    var id: String { title }
}
struct TextSetting: Identifiable {
    let title: String
    let key: WritableKeyPath<FeatureSettings, String>
    var id: String { title }
}
@MainActor
enum SettingsCatalog {
    static let tabs = ["General", "Window Switcher", "Dock Previews", "Custom Dock", "Command-Tab", "Appearance", "Capture", "Gestures", "Widgets", "Filters", "Automation", "Permissions"]
    static func toggles(_ tab: String) -> [BooleanSetting] {
        switch tab {
        case "General": [
            .init(title: "Show menu bar icon", key: \.showMenuBarIcon),
            .init(title: "Reduce motion", key: \.reducedMotion),
            .init(title: "Local debug logging", key: \.debugLogging),
            .init(title: "Automatic update checks (network opt-in)", key: \.updatesEnabled)]
        case "Window Switcher": [
            .init(title: "Enable window switcher", key: \.switcherEnabled),
            .init(title: "Release initializer modifier to select", key: \.commitOnRelease),
            .init(title: "Show switcher instantly", key: \.instantSwitcher),
            .init(title: "Start on second window", key: \.startOnSecond),
            .init(title: "Pass arrow keys through to system", key: \.passArrowsThrough),
            .init(title: "Alternate shortcut limits to active app", key: \.alternateActiveAppOnly),
            .init(title: "Open new window for windowless apps", key: \.openNewWindowForWindowless),
            .init(title: "Enable search", key: \.searchEnabled), .init(title: "Vim navigation when search is empty", key: \.vimNavigation),
            .init(title: "Select windows on pointer hover", key: \.hoverSelection), .init(title: "Include minimized and hidden windows", key: \.includeHidden),
            .init(title: "Show apps without windows", key: \.showWindowlessApps), .init(title: "Limit to active application", key: \.activeAppOnly),
            .init(title: "Current Space only", key: \.currentSpaceOnly), .init(title: "Current display only", key: \.currentDisplayOnly),
            .init(title: "Sort hidden and minimized windows last", key: \.minimizedLast), .init(title: "Collapse native tabs", key: \.collapseNativeTabs),
            .init(title: "Move pointer to focused window", key: \.mouseFollowsFocus)]
        case "Dock Previews": [
            .init(title: "Delay only the first Dock preview", key: \.dockOnlyInitialDelay),
            .init(title: "Anchor Dock preview to initial icon position", key: \.anchorDockPreview),
            .init(title: "Keep preview after hover focus", key: \.keepPreviewAfterFocus),
            .init(title: "Keep preview after app terminates", key: \.keepPreviewOnTerminate),
            .init(title: "Prevent Dock hiding during previews", key: \.preventDockHide),
            .init(title: "Quit app after last window closes", key: \.quitAfterLastWindowClosed),
            .init(title: "Enable Dock previews", key: \.dockEnabled), .init(title: "Current Space only", key: \.dockCurrentSpaceOnly),
            .init(title: "Current display only", key: \.dockCurrentDisplayOnly), .init(title: "Include minimized and hidden windows", key: \.dockIncludeHidden),
            .init(title: "Show apps without windows", key: \.dockShowWindowless), .init(title: "Ignore apps with one window", key: \.dockIgnoreSingleWindow),
            .init(title: "Group app instances", key: \.dockGroupInstances), .init(title: "Focus window on preview hover", key: \.dockHoverFocus),
            .init(title: "Hide active app on Dock click", key: \.dockClickHide), .init(title: "Restore minimized windows on Dock click", key: \.dockRestoreMinimized),
            .init(title: "Command-right-click to quit (Option force quits)", key: \.dockQuickQuit), .init(title: "Scroll Dock icons to activate or hide", key: \.dockScroll),
            .init(title: "Lock Dock to a display", key: \.dockLock), .init(title: "Show active app indicator", key: \.indicator), .init(title: "Automatically size indicator", key: \.indicatorAutoSize)]
        case "Custom Dock": [
            .init(title: "Show AltTabber Dock", key: \.customDockEnabled),
            .init(title: "Show AltTabber Dock on all displays", key: \.customDockShowOnAllDisplays),
            .init(title: "Preview windows on icon hover", key: \.customDockHoverPreviews),
            .init(title: "Hide frontmost app when clicked", key: \.customDockActiveClickHides),
            .init(title: "Switch Dock profile with focused app", key: \.customDockAppSenseEnabled),
            .init(title: "Show file tray", key: \.customDockFileTrayEnabled)]
        case "Command-Tab": [
            .init(title: "Enhance native Command-Tab", key: \.cmdTabEnabled), .init(title: "Automatically select first window", key: \.cmdTabAutoSelect),
            .init(title: "Current Space only", key: \.cmdTabCurrentSpaceOnly), .init(title: "Current display only", key: \.cmdTabCurrentDisplayOnly),
            .init(title: "Include minimized and hidden windows", key: \.cmdTabIncludeHidden), .init(title: "Show apps without windows", key: \.cmdTabShowWindowless),
            .init(title: "Ignore apps with one window", key: \.cmdTabIgnoreSingleWindow)]
        case "Appearance": [
            .init(title: "Show bulk window actions", key: \.showMassActions),
            .init(title: "Show window controls", key: \.showControls), .init(title: "Show app headers", key: \.showAppHeader),
            .init(title: "Show window status and Space badges", key: \.showBadges), .init(title: "Keep preview aspect ratio", key: \.keepAspectRatio),
            .init(title: "Anchor switcher to top", key: \.anchorTop)]
        case "Capture": [
            .init(title: "Disable window images (icons only)", key: \.disableImages),
            .init(title: "Include windows smaller than 100px", key: \.showSmallWindows),
            .init(title: "Live video in Dock previews", key: \.liveDock), .init(title: "Live video in window switcher", key: \.liveSwitcher),
            .init(title: "Stream only selected app windows", key: \.liveSelectedAppOnly)]
        case "Gestures": [
            .init(title: "Enable gestures on previews", key: \.previewGestures), .init(title: "Open switcher with global trackpad swipe", key: \.globalSwipe),
            .init(title: "Use vertical global swipes", key: \.globalSwipeVertical),
            .init(title: "Scroll active window title bar to resize", key: \.titleBarScroll), .init(title: "Shake preview to minimize other windows", key: \.shakeMinimizeOthers)]
        case "Widgets": [
            .init(title: "Folder previews", key: \.foldersEnabled), .init(title: "Show hidden files", key: \.folderShowHidden),
            .init(title: "Sort folders descending", key: \.folderDescending), .init(title: "Remember folder sorting", key: \.folderRememberSort),
            .init(title: "Calendar widget", key: \.calendarEnabled), .init(title: "Media controls", key: \.mediaEnabled),
            .init(title: "Show widgets alongside windows", key: \.embeddedWidgets), .init(title: "Allow pinning widgets", key: \.pinWidgets),
            .init(title: "Scroll media widget to seek (off adjusts volume)", key: \.mediaScrollSeek),
            .init(title: "Online lyrics (network opt-in)", key: \.lyricsEnabled)]
        default: []
        }
    }
    static func numbers(_ tab: String) -> [NumberSetting] {
        switch tab {
        case "Dock Previews": [
            .init(title: "Distance from Dock", key: \.dockBuffer, range: -40...100),
            .init(title: "Fade-out duration", key: \.fadeDuration, range: 0...2),
            .init(title: "Indicator height", key: \.indicatorHeight, range: 1...20),
            .init(title: "Indicator length", key: \.indicatorLength, range: 4...150),
            .init(title: "Indicator offset", key: \.indicatorOffset, range: -20...40),
            .init(title: "Indicator shift", key: \.indicatorShift, range: -80...80),
            .init(title: "Open delay (seconds)", key: \.dockOpenDelay, range: 0...5),
            .init(title: "Dismiss delay (seconds)", key: \.dockDismissDelay, range: 0.1...5),
            .init(title: "Hover focus delay (seconds)", key: \.dockHoverFocusDelay, range: 0.1...5)]
        case "Window Switcher": [
            .init(title: "Hover auto-scroll duration", key: \.hoverScrollDuration, range: 0...0.5)]
        case "Appearance": [
            .init(title: "Preview width (0 uses adaptive sizing)", key: \.previewWidth, range: 0...900),
            .init(title: "Preview height", key: \.previewHeight, range: 0...600), .init(title: "Corner radius", key: \.cornerRadius, range: 0...40),
            .init(title: "Spacing", key: \.spacing, range: 0...40), .init(title: "Opacity", key: \.backgroundOpacity, range: 0.1...1),
            .init(title: "Horizontal offset (%)", key: \.horizontalOffset, range: -45...45), .init(title: "Vertical offset (%)", key: \.verticalOffset, range: -45...45)]
        case "Capture": [
            .init(title: "Thumbnail cache (seconds)", key: \.cacheSeconds, range: 0...3600), .init(title: "Capture resolution scale", key: \.captureScale, range: 0.25...2),
            .init(title: "Switcher live resolution scale", key: \.liveScale, range: 0.1...1),
            .init(title: "Dock live resolution scale", key: \.dockLiveScale, range: 0.1...1), .init(title: "Stream keep-alive (seconds)", key: \.liveKeepAlive, range: 0...30)]
        case "Gestures": [.init(title: "Swipe threshold", key: \.swipeThreshold, range: 10...500),
            .init(title: "Title bar centered width scale", key: \.titleBarWidthScale, range: 0.2...1),
            .init(title: "Title bar centered height scale", key: \.titleBarHeightScale, range: 0.2...1),
            .init(title: "Title bar restore interval", key: \.titleBarRestoreInterval, range: 0.2...5)]
        default: []
        }
    }
    static func texts(_ tab: String) -> [TextSetting] {
        switch tab {
        case "Filters": [.init(title: "Excluded app names or bundle IDs (one per line)", key: \.excludedApps),
            .init(title: "Excluded window titles (one per line)", key: \.excludedTitles), .init(title: "Fullscreen app blacklist (bundle IDs)", key: \.fullscreenBlacklist),
            .init(title: "Group switcher apps (bundle IDs)", key: \.groupedApps), .init(title: "Excluded widget apps (names)", key: \.widgetExclusions),
            .init(title: "Excluded calendars (names or identifiers)", key: \.calendarExclusions)]
        default: []
        }
    }
}
