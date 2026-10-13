import XCTest
@testable import AltTabber

final class SwitcherPanelLayoutMetricsTests: XCTestCase {
    func testPanelUsesMostOfTheAvailableScreenWidth() {
        let metrics = makeMetrics(itemCount: 4)

        XCTAssertEqual(metrics.panelSize.width, 1_324.8, accuracy: 0.1)
        XCTAssertEqual(metrics.columnCount, 4)
    }

    func testFewWindowsExpandToFillTheSwitcher() {
        let twoWindows = makeMetrics(itemCount: 2)
        let fourWindows = makeMetrics(itemCount: 4)

        XCTAssertGreaterThan(twoWindows.previewSize.width, 600)
        XCTAssertGreaterThan(twoWindows.previewSize.width, fourWindows.previewSize.width)
    }

    func testManyWindowsRetainConfiguredColumnCountAndScrollVertically() {
        let metrics = makeMetrics(itemCount: 20)

        XCTAssertEqual(metrics.columnCount, 4)
        XCTAssertEqual(metrics.panelSize.height, 774, accuracy: 0.1)
        XCTAssertGreaterThan(metrics.previewSize.width, PreviewSize.standard.width)
    }

    func testHorizontalLayoutExpandsFewWindows() {
        let metrics = SwitcherPanelLayoutMetrics.calculate(
            itemCount: 2,
            screenSize: CGSize(width: 1_440, height: 900),
            layout: .horizontal,
            preferredPreviewSize: .standard,
            requestedColumnCount: 4
        )

        XCTAssertGreaterThan(metrics.previewSize.width, 600)
        XCTAssertEqual(metrics.panelSize.width, 1_324.8, accuracy: 0.1)
    }

    private func makeMetrics(itemCount: Int) -> SwitcherPanelLayoutMetrics {
        SwitcherPanelLayoutMetrics.calculate(
            itemCount: itemCount,
            screenSize: CGSize(width: 1_440, height: 900),
            layout: .grid,
            preferredPreviewSize: .standard,
            requestedColumnCount: 4
        )
    }
}
