import AppKit
import ApplicationServices
import CoreGraphics
import OSLog
import ScreenCaptureKit

struct ThumbnailLoadResult {
    let images: [(CGWindowID, NSImage)]
    let titles: [CGWindowID: String]
    let failureDescription: String?
}

private struct ThumbnailCaptureRequest: @unchecked Sendable {
    let windowID: CGWindowID
    let bounds: CGRect
    let window: SCWindow
}

private struct ThumbnailCapture: @unchecked Sendable {
    let windowID: CGWindowID
    let image: CGImage?
    let failureDescription: String?
}

@MainActor
final class WindowService {
    private let logger = Logger(subsystem: "com.local.AltTabber", category: "WindowPreviews")
    private let thumbnailCache = ThumbnailCache()
    private let ignoredOwners = Set([
        "AltTabber", "Dock", "Window Server", "Control Center", "Notification Center"
    ])

    func visibleWindows() -> [WindowItem] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seen = Set<CGWindowID>()
        var accessibilityTitleCache: [pid_t: [CGWindowID: String]] = [:]
        return rawWindows.compactMap { entry in
            guard
                let windowID = number(entry[kCGWindowNumber as String])?.uint32Value,
                let processID = number(entry[kCGWindowOwnerPID as String])?.int32Value,
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let layer = number(entry[kCGWindowLayer as String])?.intValue,
                let boundsValue = entry[kCGWindowBounds as String],
                let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
                layer == 0,
                processID != getpid(),
                !ignoredOwners.contains(owner),
                bounds.width >= 100,
                bounds.height >= 80,
                seen.insert(windowID).inserted
            else { return nil }

            let alpha = number(entry[kCGWindowAlpha as String])?.doubleValue ?? 1
            guard alpha > 0 else { return nil }

            let capturedTitle = ((entry[kCGWindowName as String] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let accessibilityTitles: [CGWindowID: String]
            if capturedTitle.isEmpty || capturedTitle.localizedCaseInsensitiveCompare(owner) == .orderedSame {
                if let cachedTitles = accessibilityTitleCache[processID] {
                    accessibilityTitles = cachedTitles
                } else {
                    let discoveredTitles = accessibilityWindowTitles(for: processID)
                    accessibilityTitleCache[processID] = discoveredTitles
                    accessibilityTitles = discoveredTitles
                }
            } else {
                accessibilityTitles = [:]
            }
            let title = accessibilityTitles[windowID] ?? capturedTitle
            let icon = NSRunningApplication(processIdentifier: processID)?.icon
                ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: owner)
                ?? NSImage()

            return WindowItem(
                id: windowID,
                processID: processID,
                appName: owner,
                title: title,
                bounds: bounds,
                appIcon: icon,
                thumbnail: nil
            )
        }
    }

    func loadThumbnails(for items: [WindowItem]) async -> ThumbnailLoadResult {
        guard !items.isEmpty else {
            return ThumbnailLoadResult(images: [], titles: [:], failureDescription: nil)
        }

        thumbnailCache.removeExpiredEntries()
        var cachedImages: [(CGWindowID, NSImage)] = []
        var uncachedItems: [WindowItem] = []
        for item in items {
            if let image = thumbnailCache.image(for: item) {
                cachedImages.append((item.id, image))
            } else {
                uncachedItems.append(item)
            }
        }

        guard !uncachedItems.isEmpty else {
            return ThumbnailLoadResult(
                images: cachedImages,
                titles: [:],
                failureDescription: nil
            )
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            let captureWindows = Dictionary(
                uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) }
            )

            var requests: [ThumbnailCaptureRequest] = []
            var titles: [CGWindowID: String] = [:]
            for item in items {
                guard !Task.isCancelled, let window = captureWindows[item.id] else { continue }
                if let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    titles[item.id] = title
                }
            }
            for item in uncachedItems {
                guard !Task.isCancelled, let window = captureWindows[item.id] else { continue }
                requests.append(ThumbnailCaptureRequest(
                    windowID: item.id,
                    bounds: item.bounds,
                    window: window
                ))
            }

            let captures = await captureThumbnails(requests)
            var results = cachedImages
            var lastFailureDescription: String?
            let itemsByID = Dictionary(uniqueKeysWithValues: uncachedItems.map { ($0.id, $0) })
            for capture in captures {
                guard !Task.isCancelled else { break }
                if let image = capture.image, let item = itemsByID[capture.windowID] {
                    let thumbnail = NSImage(cgImage: image, size: .zero)
                    thumbnailCache.insert(thumbnail, for: item)
                    results.append((capture.windowID, thumbnail))
                } else if let failureDescription = capture.failureDescription {
                    lastFailureDescription = failureDescription
                    logger.error("Preview capture failed for window \(capture.windowID): \(failureDescription, privacy: .public)")
                }
            }

            if results.isEmpty, let lastFailureDescription {
                return ThumbnailLoadResult(
                    images: [],
                    titles: titles,
                    failureDescription: lastFailureDescription
                )
            }
            return ThumbnailLoadResult(images: results, titles: titles, failureDescription: nil)
        } catch {
            logger.error("Window preview discovery failed: \(error.localizedDescription, privacy: .public)")
            return ThumbnailLoadResult(
                images: cachedImages,
                titles: [:],
                failureDescription: cachedImages.isEmpty ? error.localizedDescription : nil
            )
        }
    }

    func invalidateThumbnails(for windowIDs: Set<CGWindowID>) {
        thumbnailCache.invalidate(windowIDs: windowIDs)
    }

    @discardableResult
    func focus(_ item: WindowItem) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: item.processID) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(item.processID)
        var rawWindows: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )

        if copyResult == .success, let axWindows = rawWindows as? [AXUIElement] {
            for axWindow in axWindows {
                var rawWindowNumber: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    axWindow,
                    "AXWindowNumber" as CFString,
                    &rawWindowNumber
                )
                if result == .success,
                   let number = rawWindowNumber as? NSNumber,
                   number.uint32Value == item.id {
                    application.activate()
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
        }

        return application.activate()
    }

    private func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private func captureThumbnails(
        _ requests: [ThumbnailCaptureRequest]
    ) async -> [ThumbnailCapture] {
        let maximumConcurrentCaptures = 6
        return await withTaskGroup(of: ThumbnailCapture.self) { group in
            var iterator = requests.makeIterator()
            var captures: [ThumbnailCapture] = []
            captures.reserveCapacity(requests.count)

            for _ in 0..<min(maximumConcurrentCaptures, requests.count) {
                if let request = iterator.next() {
                    group.addTask { await Self.captureThumbnail(request) }
                }
            }

            while let capture = await group.next() {
                captures.append(capture)
                if let request = iterator.next() {
                    group.addTask { await Self.captureThumbnail(request) }
                }
            }
            return captures
        }
    }

    private nonisolated static func captureThumbnail(
        _ request: ThumbnailCaptureRequest
    ) async -> ThumbnailCapture {
        let filter = SCContentFilter(desktopIndependentWindow: request.window)
        let configuration = SCStreamConfiguration()
        configuration.width = min(Int(request.bounds.width * 2), 900)
        configuration.height = min(Int(request.bounds.height * 2), 600)
        configuration.scalesToFit = true
        configuration.showsCursor = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return ThumbnailCapture(
                windowID: request.windowID,
                image: image,
                failureDescription: nil
            )
        } catch {
            return ThumbnailCapture(
                windowID: request.windowID,
                image: nil,
                failureDescription: error.localizedDescription
            )
        }
    }

    private func accessibilityWindowTitles(for processID: pid_t) -> [CGWindowID: String] {
        let application = AXUIElementCreateApplication(processID)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &rawWindows
        ) == .success,
        let windows = rawWindows as? [AXUIElement] else {
            return [:]
        }

        var titles: [CGWindowID: String] = [:]
        for window in windows {
            var rawWindowNumber: CFTypeRef?
            var rawTitle: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                "AXWindowNumber" as CFString,
                &rawWindowNumber
            ) == .success,
            let windowNumber = rawWindowNumber as? NSNumber,
            AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &rawTitle
            ) == .success,
            let title = (rawTitle as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty else { continue }

            titles[windowNumber.uint32Value] = title
        }
        return titles
    }
}
