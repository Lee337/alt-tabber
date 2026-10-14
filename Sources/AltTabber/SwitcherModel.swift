import AppKit
import Combine

@MainActor
final class SwitcherModel: ObservableObject {
    @Published private(set) var entries: [SelectionEntry] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var gridColumnCount = 1
    @Published private(set) var previewWidth = PreviewSize.standard.width
    @Published private(set) var previewHeight = PreviewSize.standard.height
    @Published var searchText = "" { didSet { filterEntries() } }
    @Published var actionMessage: String?
    @Published var surface: PresentationSurface = .switcher
    @Published var releaseHint = "Release ⌥ to switch"
    var windows: [WindowItem] { entries.compactMap(\.window) }
    var cardFrames: [String: CGRect] = [:]
    var sourceEntries: [SelectionEntry] = []
    var settings = FeatureSettings()
    var onCommit: ((WindowItem) -> Void)?
    var onEntryCommit: ((SelectionEntry) -> Void)?
    var onCancel: (() -> Void)?
    var onAction: ((WindowAction, SelectionEntry) -> Void)?
    var onLargePreview: (() -> Void)?
    var isActionAvailable: ((WindowAction, SelectionEntry) -> Bool)?
    var onVisibleEntriesChanged: (() -> Void)?
    var onUserSelection: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var selectedEntry: SelectionEntry? { entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil }
    var selectedWindow: WindowItem? { selectedEntry?.window }

    func replaceWindows(_ newWindows: [WindowItem]) { replaceEntries(newWindows.map(SelectionEntry.window)) }
    func replaceEntries(_ values: [SelectionEntry], preserveSelection: Bool = false) {
        let identity = preserveSelection ? selectedEntry?.id : nil
        if !preserveSelection { selectedIndex = 0; entries = [] }
        sourceEntries = values
        filterEntries(preserving: identity)
    }
    private func filterEntries(preserving identity: String? = nil) {
        let selectedID = identity ?? selectedEntry?.id
        let previousID = selectedEntry?.id
        entries = sourceEntries.filter { searchText.isEmpty || FuzzySearch.matches(searchText,
            in: "\($0.appName) \($0.title)", fuzziness: settings.searchFuzziness) }
        selectedIndex = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? min(selectedIndex, max(0, entries.count - 1))
        if previousID != selectedEntry?.id { onSelectionChanged?() }
    }
    func cycle(backwards: Bool) {
        guard !entries.isEmpty else { return }
        onUserSelection?()
        selectedIndex = (selectedIndex + (backwards ? -1 : 1) + entries.count) % entries.count
        onSelectionChanged?()
    }
    func move(_ offset: Int) {
        guard !entries.isEmpty else { return }
        onUserSelection?()
        selectedIndex = min(entries.count - 1, max(0, selectedIndex + offset))
        onSelectionChanged?()
    }
    func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        onUserSelection?()
        selectedIndex = index
        onSelectionChanged?()
    }
    func setGridColumnCount(_ count: Int) { gridColumnCount = max(1, count) }
    func setPreviewSize(_ size: CGSize) { previewWidth = max(1, size.width); previewHeight = max(1, size.height) }
    func commit() {
        guard let entry = selectedEntry else { onCancel?(); return }
        if let onEntryCommit { onEntryCommit(entry) } else if let window = entry.window { onCommit?(window) }
    }
    func cancel() { onCancel?() }
    func perform(_ action: WindowAction, entry: SelectionEntry? = nil) {
        guard let target = entry ?? selectedEntry else { return }
        onAction?(action, target)
    }
    func setThumbnail(_ image: NSImage, for windowID: CGWindowID) {
        updateWindow(windowID) { $0.thumbnail = image }
    }
    func setTitle(_ title: String, for windowID: CGWindowID) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateWindow(windowID) { $0.title = cleaned }
    }
    private func updateWindow(_ id: CGWindowID, change: (inout WindowItem) -> Void) {
        for index in sourceEntries.indices {
            if var window = sourceEntries[index].window, window.id == id {
                change(&window); sourceEntries[index] = .window(window)
            }
        }
        filterEntries()
    }
}
