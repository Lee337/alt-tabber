import XCTest
@testable import AltTabber

@MainActor
final class AppSettingsTests: XCTestCase {
    func testAppearanceSettingsPersist() {
        let suiteName = "AltTabberTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.layout = .horizontal
        settings.gridColumns = 6
        settings.previewSize = .large
        settings.showWindowTitles = false

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.layout, .horizontal)
        XCTAssertEqual(restored.gridColumns, 6)
        XCTAssertEqual(restored.previewSize, .large)
        XCTAssertFalse(restored.showWindowTitles)
    }

    func testGridColumnsAreClamped() {
        let suiteName = "AltTabberTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.gridColumns = 20

        XCTAssertEqual(settings.gridColumns, 6)
    }

    func testPreviewStatusCanBeUpdated() {
        let suiteName = "AltTabberTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.setPreviewStatus(.ready(3))

        XCTAssertEqual(settings.previewStatus, .ready(3))
        XCTAssertEqual(settings.previewStatus.title, "3 previews ready")
    }
}
