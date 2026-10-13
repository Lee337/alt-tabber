import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
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

struct AccessibilityWindowCandidate {
    let title: String
    let bounds: CGRect?
}

enum AccessibilityWindowMatcher {
    static func bestMatchIndex(
        targetTitle: String,
        targetBounds: CGRect,
        candidates: [AccessibilityWindowCandidate]
    ) -> Int? {
        let normalizedTargetTitle = normalize(targetTitle)
        let matches: [(index: Int, score: CGFloat)] = candidates.enumerated().compactMap {
            index, candidate -> (index: Int, score: CGFloat)? in
            let titleMatches = !normalizedTargetTitle.isEmpty
                && normalize(candidate.title) == normalizedTargetTitle
            let frameDifference = candidate.bounds.map {
                maximumFrameDifference($0, targetBounds)
            }
            let frameMatches = frameDifference.map { $0 <= 16 } ?? false
            guard titleMatches || frameMatches else { return nil }

            let score: CGFloat
            if frameMatches {
                score = (frameDifference ?? 0) + (titleMatches ? 0 : 1_000)
            } else {
                score = 10_000 + (frameDifference ?? 0)
            }
            return (index: index, score: score)
        }
        return matches.min { lhs, rhs in lhs.score < rhs.score }?.index
    }

    private static func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func maximumFrameDifference(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(
            abs(lhs.minX - rhs.minX),
            abs(lhs.minY - rhs.minY),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        )
    }
}

@MainActor
final class WindowService {
    private typealias CopyWindowIDFunction = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private static let copyWindowIDFunction: CopyWindowIDFunction? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CopyWindowIDFunction.self)
    }()

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

        guard PermissionManager.hasAccessibilityAccess else {
            logger.error("Accessibility permission is unavailable; activating \(item.appName, privacy: .public) without exact window focus")
            return application.activate()
        }

        let appElement = AXUIElementCreateApplication(item.processID)
        var rawWindows: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        )

        if copyResult == .success, let axWindows = rawWindows as? [AXUIElement] {
            if let targetWindow = matchingWindow(for: item, in: axWindows) {
                return focus(
                    targetWindow,
                    in: appElement,
                    application: application,
                    windowID: item.id
                )
            }
        } else {
            logger.error("Could not read Accessibility windows for \(item.appName, privacy: .public): AX error \(copyResult.rawValue)")
        }

        logger.error("Could not resolve Accessibility window \(item.id) for \(item.appName, privacy: .public)")
        return application.activate()
    }

    private func matchingWindow(
        for item: WindowItem,
        in windows: [AXUIElement]
    ) -> AXUIElement? {
        if let exactMatch = windows.first(where: { windowID(for: $0) == item.id }) {
            return exactMatch
        }

        let candidates = windows.map {
            AccessibilityWindowCandidate(title: windowTitle(for: $0), bounds: windowFrame(for: $0))
        }
        guard let index = AccessibilityWindowMatcher.bestMatchIndex(
            targetTitle: item.title,
            targetBounds: item.bounds,
            candidates: candidates
        ) else { return nil }
        return windows[index]
    }

    private func focus(
        _ window: AXUIElement,
        in applicationElement: AXUIElement,
        application: NSRunningApplication,
        windowID: CGWindowID
    ) -> Bool {
        let raisedBeforeActivation = AXUIElementPerformAction(
            window,
            kAXRaiseAction as CFString
        )
        let activated = application.activate()
        let frontmost = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        let focused = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window
        )
        let main = AXUIElementSetAttributeValue(
            window,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        let raisedAfterActivation = AXUIElementPerformAction(
            window,
            kAXRaiseAction as CFString
        )
        _ = AXUIElementSetAttributeValue(
            window,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        let selectedExactWindow = focused == .success
            || main == .success
            || raisedBeforeActivation == .success
            || raisedAfterActivation == .success
        if !selectedExactWindow {
            logger.error("Accessibility could not focus selected window \(windowID)")
        }
        return (activated || frontmost == .success) && selectedExactWindow
    }

    private func windowID(for window: AXUIElement) -> CGWindowID? {
        if let copyWindowIDFunction = Self.copyWindowIDFunction {
            var windowID = CGWindowID(0)
            if copyWindowIDFunction(window, &windowID) == .success, windowID != 0 {
                return windowID
            }
        }

        var rawWindowNumber: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            "AXWindowNumber" as CFString,
            &rawWindowNumber
        ) == .success,
        let number = rawWindowNumber as? NSNumber else { return nil }
        return number.uint32Value
    }

    private func windowTitle(for window: AXUIElement) -> String {
        var rawTitle: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &rawTitle
        ) == .success else { return "" }
        return (rawTitle as? String) ?? ""
    }

    private func windowFrame(for window: AXUIElement) -> CGRect? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &rawPosition
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &rawSize
        ) == .success,
        let rawPosition,
        let rawSize,
        CFGetTypeID(rawPosition) == AXValueGetTypeID(),
        CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }

        let positionValue = rawPosition as! AXValue
        let sizeValue = rawSize as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
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
            guard let windowID = windowID(for: window) else { continue }
            let title = windowTitle(for: window).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            titles[windowID] = title
        }
        return titles
    }
}
