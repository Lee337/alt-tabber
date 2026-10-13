import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ThumbnailCache {
    private struct Entry {
        let image: NSImage
        let processID: pid_t
        let windowSize: CGSize
        let expiresAt: Date
    }

    private let timeToLive: TimeInterval
    private let now: () -> Date
    private var entries: [CGWindowID: Entry] = [:]

    init(
        timeToLive: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.timeToLive = timeToLive
        self.now = now
    }

    func image(for item: WindowItem) -> NSImage? {
        guard let entry = entries[item.id] else { return nil }
        guard entry.expiresAt > now(),
              entry.processID == item.processID,
              entry.windowSize == normalizedSize(item.bounds.size) else {
            entries.removeValue(forKey: item.id)
            return nil
        }
        return entry.image
    }

    func insert(_ image: NSImage, for item: WindowItem) {
        entries[item.id] = Entry(
            image: image,
            processID: item.processID,
            windowSize: normalizedSize(item.bounds.size),
            expiresAt: now().addingTimeInterval(timeToLive)
        )
    }

    func removeExpiredEntries() {
        let currentDate = now()
        entries = entries.filter { $0.value.expiresAt > currentDate }
    }

    func invalidate(windowIDs: Set<CGWindowID>) {
        for windowID in windowIDs {
            entries.removeValue(forKey: windowID)
        }
    }

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(), height: size.height.rounded())
    }
}
