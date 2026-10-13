import XCTest
@testable import AltTabber

@MainActor
final class SwitcherModelTests: XCTestCase {
    func testCyclingWrapsInBothDirections() {
        let model = SwitcherModel()
        model.replaceWindows([
            makeWindow(id: 1),
            makeWindow(id: 2),
            makeWindow(id: 3)
        ])

        model.cycle(backwards: true)
        XCTAssertEqual(model.selectedWindow?.id, 3)

        model.cycle(backwards: false)
        XCTAssertEqual(model.selectedWindow?.id, 1)
    }

    func testCommitUsesSelectedWindow() {
        let model = SwitcherModel()
        model.replaceWindows([makeWindow(id: 10), makeWindow(id: 20)])
        model.select(1)
        var committedID: CGWindowID?
        model.onCommit = { committedID = $0.id }

        model.commit()

        XCTAssertEqual(committedID, 20)
    }

    func testGridColumnCountNeverCollapsesBelowOne() {
        let model = SwitcherModel()

        model.setGridColumnCount(0)

        XCTAssertEqual(model.gridColumnCount, 1)
    }

    func testPreviewSizeNeverCollapsesBelowOnePoint() {
        let model = SwitcherModel()

        model.setPreviewSize(CGSize(width: 0, height: -10))

        XCTAssertEqual(model.previewWidth, 1)
        XCTAssertEqual(model.previewHeight, 1)
    }

    func testWindowTitleCanBeEnrichedAfterDiscovery() {
        let model = SwitcherModel()
        var window = makeWindow(id: 42)
        window.title = ""
        model.replaceWindows([window])

        model.setTitle("Downloads", for: 42)

        XCTAssertEqual(model.selectedWindow?.displayTitle, "Downloads")
        XCTAssertTrue(model.selectedWindow?.hasDistinctTitle == true)
    }

    private func makeWindow(id: CGWindowID) -> WindowItem {
        WindowItem(
            id: id,
            processID: 1,
            appName: "Test",
            title: "Window \(id)",
            bounds: CGRect(x: 0, y: 0, width: 600, height: 400),
            appIcon: NSImage(),
            thumbnail: nil
        )
    }
}
