import XCTest
@testable import AltTabber

final class AccessibilityWindowMatcherTests: XCTestCase {
    func testExactFrameAndTitleSelectTheMatchingWindow() {
        let candidates = [
            candidate(title: "Inbox", x: 20),
            candidate(title: "Downloads", x: 600)
        ]

        let match = AccessibilityWindowMatcher.bestMatchIndex(
            targetTitle: "Downloads",
            targetBounds: CGRect(x: 600, y: 40, width: 500, height: 400),
            candidates: candidates
        )

        XCTAssertEqual(match, 1)
    }

    func testFrameMatchSurvivesAChangedBrowserTitle() {
        let candidates = [
            candidate(title: "Updated page title", x: 600),
            candidate(title: "Original page title", x: 20)
        ]

        let match = AccessibilityWindowMatcher.bestMatchIndex(
            targetTitle: "Original page title",
            targetBounds: CGRect(x: 600, y: 40, width: 500, height: 400),
            candidates: candidates
        )

        XCTAssertEqual(match, 0)
    }

    func testTitleMatchProvidesFallbackWhenFrameIsUnavailable() {
        let candidates = [
            AccessibilityWindowCandidate(title: "Inbox", bounds: nil),
            AccessibilityWindowCandidate(title: "Downloads", bounds: nil)
        ]

        let match = AccessibilityWindowMatcher.bestMatchIndex(
            targetTitle: "Downloads",
            targetBounds: .zero,
            candidates: candidates
        )

        XCTAssertEqual(match, 1)
    }

    func testUnrelatedWindowDoesNotBecomeAnAccidentalMatch() {
        let match = AccessibilityWindowMatcher.bestMatchIndex(
            targetTitle: "Downloads",
            targetBounds: CGRect(x: 600, y: 40, width: 500, height: 400),
            candidates: [candidate(title: "Inbox", x: 20)]
        )

        XCTAssertNil(match)
    }

    private func candidate(title: String, x: CGFloat) -> AccessibilityWindowCandidate {
        AccessibilityWindowCandidate(
            title: title,
            bounds: CGRect(x: x, y: 40, width: 500, height: 400)
        )
    }
}
