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
    let scale: Double
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
    private var history: [CGWindowID: (pid_t, Date, Date)] = [:]
    var showSmallWindows = false
    var captureScale = 1.0
    var cacheSeconds: Double = 600 {
        didSet { thumbnailCache.timeToLive = cacheSeconds }
    }
    private let ignoredOwners = Set([
        "AltTabber", "Dock", "Window Server", "Control Center", "Notification Center"
    ])

    func visibleWindows() -> [WindowItem] { discoverWindows(onScreenOnly: true) }

    func entries() -> [SelectionEntry] {
        let windows = discoverWindows(onScreenOnly: false)
        let owners = Set(windows.map(\.processID))
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !owners.contains($0.processIdentifier)
        }.map { app in
            SelectionEntry.application(ApplicationItem(processID: app.processIdentifier,
                name: app.localizedName ?? "Application", bundleIdentifier: app.bundleIdentifier,
                icon: app.icon ?? NSImage()))
        }
        return windows.map(SelectionEntry.window) + applications
    }

    var frontmostIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        var flag: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(raw as! AXUIElement, "AXFullScreen" as CFString, &flag)
        return flag as? Bool ?? false
    }

    func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return windowID(for: raw as! AXUIElement)
    }

    func markUsed(_ item: WindowItem) {
        let created = history[item.id]?.1 ?? Date()
        history[item.id] = (item.processID, created, Date())
    }

    func accessibilityWindow(for item: WindowItem) -> AXUIElement? {
        let app = AXUIElementCreateApplication(item.processID)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return nil }
        // Prefer exact IDs. Apps without IDs require one unambiguous title-and-frame match.
        if let exact = windows.first(where: { windowID(for: $0) == item.id }) { return exact }
        guard windows.allSatisfy({ windowID(for: $0) == nil }) else { return nil }
        let matches = windows.filter { candidate in
            guard let frame = windowFrame(for: candidate) else { return false }
            let title = windowTitle(for: candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            return title == item.title && abs(frame.minX - item.bounds.minX) <= 2 && abs(frame.minY - item.bounds.minY) <= 2
                && abs(frame.width - item.bounds.width) <= 2 && abs(frame.height - item.bounds.height) <= 2
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func discoverWindows(onScreenOnly: Bool) -> [WindowItem] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seen = Set<CGWindowID>()
        var accessibilityTitleCache: [pid_t: [CGWindowID: String]] = [:]
        var items: [WindowItem] = rawWindows.compactMap { entry in
            guard
                let windowID = number(entry[kCGWindowNumber as String])?.uint32Value,
                let processID = number(entry[kCGWindowOwnerPID as String])?.int32Value,
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let layer = number(entry[kCGWindowLayer as String])?.intValue,
                let boundsValue = entry[kCGWindowBounds as String],
                let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary),
                layer == 0,
                processID != getpid(),
                let runningApp = NSRunningApplication(processIdentifier: processID),
                runningApp.activationPolicy == .regular,
                !ignoredOwners.contains(owner),
                bounds.width >= (showSmallWindows ? 1 : 100),
                bounds.height >= (showSmallWindows ? 1 : 80),
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
        var accessibilityIDs = Set<CGWindowID>()
        var byID = Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            var raw: CFTypeRef?
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
                  let windows = raw as? [AXUIElement] else { continue }
            for window in windows {
                guard let id = windowID(for: window), let bounds = windowFrame(for: window) else { continue }
                accessibilityIDs.insert(id)
                var value: CFTypeRef?
                func flag(_ key: String) -> Bool {
                    value = nil
                    _ = AXUIElementCopyAttributeValue(window, key as CFString, &value)
                    return value as? Bool ?? false
                }
                let minimized = flag(kAXMinimizedAttribute)
                if onScreenOnly && byID[id] == nil { continue }
                if byID[id] == nil {
                    guard bounds.width >= (showSmallWindows ? 1 : 100), bounds.height >= (showSmallWindows ? 1 : 80) else { continue }
                    byID[id] = items.count
                    items.append(WindowItem(id: id, processID: app.processIdentifier, appName: app.localizedName ?? "Application",
                        title: windowTitle(for: window), bounds: bounds, appIcon: app.icon ?? NSImage(), thumbnail: nil))
                }
                if let index = byID[id] {
                    items[index].isMinimized = minimized
                    items[index].isHidden = app.isHidden
                    items[index].isFullscreen = flag("AXFullScreen")
                    let title = windowTitle(for: window)
                    if !title.isEmpty { items[index].title = title }
                }
            }
        }
        let onScreen = Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostID = focusedWindowID() ?? items.first { $0.processID == frontmostPID && !$0.isMinimized }?.id
        for index in items.indices {
            let item = items[index]
            let previous = history[item.id].flatMap { $0.0 == item.processID ? $0 : nil }
            let created = previous?.1 ?? Date()
            let used = item.id == frontmostID ? Date() : previous?.2 ?? .distantPast
            history[item.id] = (item.processID, created, used)
            items[index].isOnScreen = onScreen.contains(item.id)
            items[index].createdAt = created
            items[index].lastUsedAt = used
            items[index].bundleIdentifier = NSRunningApplication(processIdentifier: item.processID)?.bundleIdentifier
            items[index].spaceIDs = PlatformCapabilities.shared.spaces(for: item.id)
            var displays = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            if CGGetDisplaysWithRect(item.bounds, 16, &displays, &count) == .success, count > 0 {
                items[index].displayID = displays[0]
            }
        }
        // CoreGraphics includes retained backing surfaces and helper windows. Off-screen
        // entries must be confirmed by Accessibility rather than presented as live windows.
        items = items.filter { $0.isOnScreen || accessibilityIDs.contains($0.id) }
        let liveIDs = Set(items.map(\.id))
        history = history.filter { liveIDs.contains($0.key) }
        let groups = Dictionary(grouping: items.indices.filter { !items[$0].isMinimized && !items[$0].isHidden }, by: { index in
            let w = items[index]
            return "\(w.processID):\(w.bounds.minX):\(w.bounds.minY):\(w.bounds.width):\(w.bounds.height)"
        })
        for (group, indices) in groups where indices.count > 1 {
            let visible = indices.filter { items[$0].isOnScreen }
            let representative = visible.first ?? indices.max { items[$0].lastUsedAt < items[$1].lastUsedAt }!
            for index in indices where !items[index].isOnScreen || index == representative {
                items[index].nativeTabGroup = group
            }
        }
        return items
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
                onScreenWindowsOnly: false
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
                    window: window,
                    scale: captureScale
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

    func captureLargePreview(for item: WindowItem, maximumPixelSize: CGSize) async -> NSImage? {
        guard !item.isMinimized, !item.isHidden, !Task.isCancelled else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard !Task.isCancelled, let window = content.windows.first(where: { $0.windowID == item.id }) else { return nil }
            let sourceSize = window.frame.width > 0 && window.frame.height > 0 ? window.frame.size : item.bounds.size
            let width = max(1, sourceSize.width)
            let height = max(1, sourceSize.height)
            let scale = min(2, 4096 / width, 3072 / height,
                            max(1, maximumPixelSize.width) / width,
                            max(1, maximumPixelSize.height) / height)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((width * scale).rounded()))
            configuration.height = max(1, Int((height * scale).rounded()))
            configuration.scalesToFit = true
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
            guard !Task.isCancelled else { return nil }
            return NSImage(cgImage: image, size: .zero)
        } catch {
            logger.debug("Large preview capture failed for window \(item.id): \(error.localizedDescription, privacy: .public)")
            return nil
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
        _ = application.unhide()
        _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
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
        configuration.width = min(Int(request.bounds.width * request.scale), 900)
        configuration.height = min(Int(request.bounds.height * request.scale), 600)
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
