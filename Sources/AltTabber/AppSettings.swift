import Combine
import Foundation
import ServiceManagement

enum SwitcherLayout: String, CaseIterable, Identifiable {
    case grid
    case horizontal

    var id: Self { self }
    var title: String { self == .grid ? "Grid" : "Horizontal" }
}

enum PreviewSize: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var width: CGFloat {
        switch self {
        case .compact: 150
        case .standard: 180
        case .large: 220
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: 90
        case .standard: 112
        case .large: 136
        }
    }
}

enum ShortcutStatus: Equatable {
    case starting
    case waitingForAccessibility
    case ready
    case unavailable

    var title: String {
        switch self {
        case .starting: "Checking…"
        case .waitingForAccessibility: "Waiting for Accessibility"
        case .ready: "Option-Tab Ready"
        case .unavailable: "Unavailable — Check for a Shortcut Conflict"
        }
    }
}

enum PreviewStatus: Equatable {
    case checking
    case ready(Int)
    case permissionRequired
    case unavailable(String)

    var title: String {
        switch self {
        case .checking:
            "Checking…"
        case .ready(let count):
            count == 1 ? "1 preview ready" : "\(count) previews ready"
        case .permissionRequired:
            "Screen Recording permission required"
        case .unavailable(let reason):
            "Unavailable — \(reason)"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let layout = "switcherLayout"
        static let gridColumns = "gridColumns"
        static let previewSize = "previewSize"
        static let showWindowTitles = "showWindowTitles"
    }

    private let defaults: UserDefaults

    @Published var layout: SwitcherLayout {
        didSet { defaults.set(layout.rawValue, forKey: Key.layout) }
    }

    @Published var gridColumns: Int {
        didSet {
            let clamped = min(max(gridColumns, 2), 6)
            if gridColumns != clamped { gridColumns = clamped }
            defaults.set(clamped, forKey: Key.gridColumns)
        }
    }

    @Published var previewSize: PreviewSize {
        didSet { defaults.set(previewSize.rawValue, forKey: Key.previewSize) }
    }

    @Published var showWindowTitles: Bool {
        didSet { defaults.set(showWindowTitles, forKey: Key.showWindowTitles) }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var shortcutStatus: ShortcutStatus = .starting
    @Published private(set) var previewStatus: PreviewStatus = .checking

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = SwitcherLayout(rawValue: defaults.string(forKey: Key.layout) ?? "") ?? .grid

        let savedColumns = defaults.integer(forKey: Key.gridColumns)
        gridColumns = savedColumns == 0 ? 4 : min(max(savedColumns, 2), 6)

        previewSize = PreviewSize(rawValue: defaults.string(forKey: Key.previewSize) ?? "") ?? .standard
        showWindowTitles = defaults.object(forKey: Key.showWindowTitles) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setShortcutStatus(_ status: ShortcutStatus) {
        shortcutStatus = status
    }

    func setPreviewStatus(_ status: PreviewStatus) {
        previewStatus = status
    }
}
