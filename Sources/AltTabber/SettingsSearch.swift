import Foundation

struct SettingsSearchResult: Identifiable {
    let tab: String
    let title: String
    var id: String { tab + ":" + title }
}
@MainActor
enum SettingsSearch {
    static var catalog: [SettingsSearchResult] {
        var entries = SettingsCatalog.tabs.flatMap { tab in
            (SettingsCatalog.toggles(tab).map(\.title) + SettingsCatalog.numbers(tab).map(\.title) + SettingsCatalog.texts(tab).map(\.title)).map { SettingsSearchResult(tab: tab, title: $0) }
        }
        let styleTitles = ["Show app header", "Use app icon only", "App icon size", "Title visibility", "Title above preview", "Title font size", "Title overflow", "Control visibility", "Controls at top", "Controls on right", "Embed controls in previews", "Monochrome controls", "Control scale", "Show minimized and hidden badges", "Show Space badges", "Appearance", "Highlight color", "Background color", "Opaque background", "Hide card backgrounds", "Hide container background", "Selection opacity", "Unselected content opacity", "Show shadow", "Shadow radius", "Shadow opacity", "Animated highlight gradient", "Gradient start", "Gradient end", "Gradient speed", "Gradient blur", "Glass saturation", "Glass blur", "Border opacity", "Border width", "Compact row height", "Compact app and window title", "Hide controls in compact mode"]
        for tab in ["Appearance", "Dock Previews", "Command-Tab"] {
            entries += styleTitles.map { SettingsSearchResult(tab: tab, title: $0) }
        }
        let extra: [String: [String]] = [
            "General": ["Launch at Login", "Update channel", "Check for Updates…", "Export Settings…", "Import Settings…", "Export Local Diagnostics…"],
            "Window Switcher": ["Sort order", "Search fuzziness", "Compact list threshold", "Primary", "Alternate", "Backward cycling key", "Selection key", "Search key", "Close key (Command)", "Minimize key (Command)", "Quit key (Command)", "Large preview during Option-Tab", "Large preview key (Command)", "Close shortcut action", "Minimize shortcut action", "Quit shortcut action"],
            "Appearance": ["Layout", "Grid columns", "Preview size", "Show window titles", "Material", "Display placement", "Pinned display"],
            "Dock Previews": ["Preview activation", "Activation modifier", "Indicator color", "Sort order", "Dock lock override", "Indicator style", "Dock lock display"],
            "Custom Dock": ["Edge", "Icon size", "Active profile and AppSense fallback", "Profile name", "Show unpinned running apps", "Linked app bundle IDs (comma-separated)", "New Profile", "Delete Profile", "Add Applications…", "Import System Dock Apps", "Add Files or Folders…", "Add Link", "Add Separator", "Add Files to Tray…", "Clear File Tray"],
            "Command-Tab": ["Sort order", "Forward window key", "Backward window key"],
            "Capture": ["Dock frame rate", "Switcher frame rate", "Preview status"],
            "Gestures": ["Middle click", "Swipe up / away from Dock", "Swipe down / toward Dock", "Global swipe fingers"],
            "Widgets": ["Default sort"], "Permissions": ["Accessibility", "Screen Recording"]
        ]
        for (tab, titles) in extra { entries += titles.map { SettingsSearchResult(tab: tab, title: $0) } }
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }
    static func results(for query: String) -> [SettingsSearchResult] {
        let tokens = query.split(separator: " ")
        return catalog.filter { entry in tokens.allSatisfy { (entry.tab + " " + entry.title).localizedCaseInsensitiveContains($0) } }
    }
}
