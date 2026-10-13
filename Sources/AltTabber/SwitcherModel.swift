import AppKit
import Combine

@MainActor
final class SwitcherModel: ObservableObject {
    @Published private(set) var windows: [WindowItem] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var gridColumnCount = 1

    var onCommit: ((WindowItem) -> Void)?
    var onCancel: (() -> Void)?

    var selectedWindow: WindowItem? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }

    func replaceWindows(_ newWindows: [WindowItem]) {
        windows = newWindows
        selectedIndex = 0
    }

    func cycle(backwards: Bool) {
        guard !windows.isEmpty else { return }
        let offset = backwards ? -1 : 1
        selectedIndex = (selectedIndex + offset + windows.count) % windows.count
    }

    func select(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        selectedIndex = index
    }

    func setGridColumnCount(_ count: Int) {
        gridColumnCount = max(1, count)
    }

    func commit() {
        guard let selectedWindow else { return }
        onCommit?(selectedWindow)
    }

    func cancel() {
        onCancel?()
    }

    func setThumbnail(_ image: NSImage, for windowID: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        windows[index].thumbnail = image
    }

    func setTitle(_ title: String, for windowID: CGWindowID) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty,
              let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        windows[index].title = cleanedTitle
    }
}
