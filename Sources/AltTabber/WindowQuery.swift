import AppKit

struct ApplicationItem: Identifiable {
    let processID: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    var id: pid_t { processID }
}

enum SelectionEntry: Identifiable {
    case window(WindowItem)
    case application(ApplicationItem)

    var id: String {
        switch self {
        case .window(let window): "window:\(window.processID):\(window.id)"
        case .application(let app): "app:\(app.processID)"
        }
    }
    var window: WindowItem? { if case .window(let w) = self { return w }; return nil }
    var processID: pid_t {
        switch self { case .window(let w): w.processID; case .application(let a): a.processID }
    }
    var appName: String {
        switch self { case .window(let w): w.appName; case .application(let a): a.name }
    }
    var title: String { window?.displayTitle ?? appName }
    var icon: NSImage {
        switch self { case .window(let w): w.appIcon; case .application(let a): a.icon }
    }
    var bundleIdentifier: String? {
        switch self { case .window(let w): w.bundleIdentifier; case .application(let a): a.bundleIdentifier }
    }
}

enum PresentationSurface { case switcher, dock, commandTab }
struct WindowQuery {
    var surface: PresentationSurface = .switcher
    var processID: pid_t?
    var currentAppID: pid_t?
    var displayID: UInt32?
    var currentSpaces: Set<UInt64>?
    var text = ""

    func apply(to entries: [SelectionEntry], settings: FeatureSettings) -> [SelectionEntry] {
        let includeHidden: Bool
        let showWindowless: Bool
        let spaceOnly: Bool
        let displayOnly: Bool
        switch surface {
        case .switcher:
            includeHidden = settings.includeHidden; showWindowless = settings.showWindowlessApps
            spaceOnly = settings.currentSpaceOnly; displayOnly = settings.currentDisplayOnly
        case .dock:
            includeHidden = settings.dockIncludeHidden; showWindowless = settings.dockShowWindowless
            spaceOnly = settings.dockCurrentSpaceOnly; displayOnly = settings.dockCurrentDisplayOnly
        case .commandTab:
            includeHidden = settings.cmdTabIncludeHidden; showWindowless = settings.cmdTabShowWindowless
            spaceOnly = settings.cmdTabCurrentSpaceOnly; displayOnly = settings.cmdTabCurrentDisplayOnly
        }
        var result = entries.filter { entry in
            if let processID, entry.processID != processID { return false }
            if surface == .switcher, settings.activeAppOnly, entry.processID != currentAppID { return false }
            if Self.tokens(settings.excludedApps).contains(where: {
                entry.appName.localizedCaseInsensitiveContains($0) || entry.bundleIdentifier?.localizedCaseInsensitiveContains($0) == true
            }) { return false }
            if Self.tokens(settings.excludedTitles).contains(where: { entry.title.localizedCaseInsensitiveContains($0) }) { return false }
            guard let w = entry.window else { return showWindowless && !spaceOnly && !displayOnly }
            if !includeHidden && (w.isHidden || w.isMinimized) { return false }
            if spaceOnly {
                guard let spaces = w.spaceIDs, let currentSpaces, !currentSpaces.isDisjoint(with: spaces) else { return false }
            }
            if displayOnly, w.displayID == nil || w.displayID != displayID { return false }
            return true
        }
        if (surface == .dock && settings.dockIgnoreSingleWindow) || (surface == .commandTab && settings.cmdTabIgnoreSingleWindow) {
            if result.filter({ $0.window != nil }).count == 1 { result = [] }
        }
        let order = Dictionary(settings.persistedOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        result.sort { a, b in
            if settings.minimizedLast {
                let x = a.window.map { $0.isMinimized || $0.isHidden } ?? true
                let y = b.window.map { $0.isMinimized || $0.isHidden } ?? true
                if x != y { return !x }
            }
            if (a.window != nil) != (b.window != nil) { return a.window != nil }
            let sort = surface == .dock ? settings.dockSortOrder : surface == .commandTab ? settings.commandTabSortOrder : settings.sortOrder
            switch sort {
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .application: return a.appName == b.appName ? a.title < b.title : a.appName < b.appName
            case .oldest: return (a.window?.createdAt ?? .distantFuture) < (b.window?.createdAt ?? .distantFuture)
            case .persistent: return (order[a.id] ?? Int.max) < (order[b.id] ?? Int.max)
            case .recent: return (a.window?.lastUsedAt ?? .distantPast) > (b.window?.lastUsedAt ?? .distantPast)
            }
        }
        var groups = Set<String>()
        result = result.filter { entry in
            if settings.collapseNativeTabs, let group = entry.window?.nativeTabGroup {
                return groups.insert("tab:\(entry.processID):\(group)").inserted
            }
            return true
        }
        if surface == .switcher, !settings.activeAppOnly {
            let selectedGroups = Set(Self.tokens(settings.groupedApps))
            var emitted = Set<String>()
            var ordered: [SelectionEntry] = []
            for entry in result {
                let group = entry.bundleIdentifier ?? entry.appName
                if selectedGroups.contains(group) {
                    guard emitted.insert(group).inserted else { continue }
                    ordered.append(contentsOf: result.filter { ($0.bundleIdentifier ?? $0.appName) == group })
                } else {
                    ordered.append(entry)
                }
            }
            result = ordered
        }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { FuzzySearch.matches(query, in: "\($0.appName) \($0.title)", fuzziness: settings.searchFuzziness) }
        }
        return result
    }

    static func tokens(_ value: String) -> [String] {
        value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum FuzzySearch {
    static func matches(_ query: String, in text: String, fuzziness: Int) -> Bool {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return q.split(separator: " ").allSatisfy { token in
            if t.contains(token) { return true }
            guard fuzziness > 1 else { return false }
            var cursor = t.startIndex
            var gaps = 0
            for character in token {
                guard cursor < t.endIndex, let next = t[cursor...].firstIndex(of: character) else { return false }
                gaps += t.distance(from: cursor, to: next)
                cursor = t.index(after: next)
            }
            return gaps <= (fuzziness - 1) * max(2, token.count)
        }
    }
}
