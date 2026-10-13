import XCTest
@testable import AltTabber

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    func testThumbnailRemainsCachedForTenMinutes() {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = ThumbnailCache(timeToLive: 600, now: { now })
        let item = makeWindow(id: 1)
        let image = NSImage(size: NSSize(width: 20, height: 20))
        cache.insert(image, for: item)

        now.addTimeInterval(599)

        XCTAssertTrue(cache.image(for: item) === image)
    }

    func testThumbnailExpiresAfterTenMinutes() {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = ThumbnailCache(timeToLive: 600, now: { now })
        let item = makeWindow(id: 1)
        cache.insert(NSImage(size: NSSize(width: 20, height: 20)), for: item)

        now.addTimeInterval(600)

        XCTAssertNil(cache.image(for: item))
    }

    func testInvalidationOnlyRemovesWindowsThatWereSwitched() {
        let cache = ThumbnailCache()
        let source = makeWindow(id: 1)
        let destination = makeWindow(id: 2)
        let untouched = makeWindow(id: 3)
        cache.insert(NSImage(), for: source)
        cache.insert(NSImage(), for: destination)
        cache.insert(NSImage(), for: untouched)

        cache.invalidate(windowIDs: [source.id, destination.id])

        XCTAssertNil(cache.image(for: source))
        XCTAssertNil(cache.image(for: destination))
        XCTAssertNotNil(cache.image(for: untouched))
    }

    func testResizingAWindowInvalidatesItsCachedThumbnail() {
        let cache = ThumbnailCache()
        let original = makeWindow(id: 1, width: 600)
        cache.insert(NSImage(), for: original)

        let resized = makeWindow(id: 1, width: 800)

        XCTAssertNil(cache.image(for: resized))
    }

    private func makeWindow(id: CGWindowID, width: CGFloat = 600) -> WindowItem {
        WindowItem(
            id: id,
            processID: 1,
            appName: "Test",
            title: "Window \(id)",
            bounds: CGRect(x: 0, y: 0, width: width, height: 400),
            appIcon: NSImage(),
            thumbnail: nil
        )
    }
}
