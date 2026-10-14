import AppKit
import ApplicationServices

enum WindowAction: String, Codable, CaseIterable, Identifiable {
    case focus, close, minimize, hide, maximize, fullscreen, quit, forceQuit, openApp, newWindow
    case currentSpace, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight, center
    var id: Self { self }
    var title: String {
        switch self {
        case .focus: "Focus"; case .close: "Close"; case .minimize: "Minimize / Restore"
        case .hide: "Hide / Unhide App"; case .maximize: "Maximize / Restore"; case .fullscreen: "Toggle Full Screen"
        case .quit: "Quit App"; case .forceQuit: "Force Quit App"; case .openApp: "Open App"; case .newWindow: "New Window"
        case .currentSpace: "Bring to Current Space"; case .left: "Left Half"; case .right: "Right Half"
        case .top: "Top Half"; case .bottom: "Bottom Half"; case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"; case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"; case .center: "Center"
        }
    }
}
enum WindowActionResult: String, Codable { case success, unsupported, permissionDenied, staleTarget, failed }

enum WindowGeometry {
    static func frame(for action: WindowAction, current: CGRect, screen: CGRect) -> CGRect {
        var frame = screen
        switch action {
        case .left: frame.size.width /= 2
        case .right: frame.size.width /= 2; frame.origin.x += frame.width
        case .top: frame.size.height /= 2
        case .bottom: frame.size.height /= 2; frame.origin.y += frame.height
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            frame.size.width /= 2; frame.size.height /= 2
            if action == .topRight || action == .bottomRight { frame.origin.x += frame.width }
            if action == .bottomLeft || action == .bottomRight { frame.origin.y += frame.height }
        case .center:
            frame.size = CGSize(width: min(current.width, screen.width), height: min(current.height, screen.height))
            frame.origin = CGPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2)
        default: break
        }
        return frame
    }
    static func accessibilityFrame(_ appKitFrame: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: appKitFrame.minX, y: desktopTop - appKitFrame.maxY, width: appKitFrame.width, height: appKitFrame.height)
    }
}

@MainActor
final class WindowActionService {
    let windows: WindowService
    private var capabilityCache: [String: (Date, Set<WindowAction>)] = [:]
    private var restoredFrames: [String: CGRect] = [:]
    init(windows: WindowService) { self.windows = windows }

    func available(_ action: WindowAction, for entry: SelectionEntry) -> Bool {
        if let cached = capabilityCache[entry.id], cached.0 > Date() { return cached.1.contains(action) }
        var supported: Set<WindowAction> = [.quit, .forceQuit, .hide, .openApp, .focus]
        if PermissionManager.hasAccessibilityAccess {
            if newWindowMenu(in: entry.processID) != nil { supported.insert(.newWindow) }
            if let item = entry.window, let element = windows.accessibilityWindow(for: item) {
                if attribute(element, kAXCloseButtonAttribute) != nil { supported.insert(.close) }
                for (action, key) in [(WindowAction.minimize, kAXMinimizedAttribute), (.fullscreen, "AXFullScreen")] {
                    var settable: DarwinBoolean = false
                    if AXUIElementIsAttributeSettable(element, key as CFString, &settable) == .success && settable.boolValue { supported.insert(action) }
                }
                if PlatformCapabilities.shared.supportsMovingSpaces { supported.insert(.currentSpace) }
                var positionSettable: DarwinBoolean = false; var sizeSettable: DarwinBoolean = false
                _ = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable)
                _ = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable)
                if positionSettable.boolValue && sizeSettable.boolValue && !item.isHidden && !item.isMinimized {
                    supported.formUnion([.maximize, .left, .right, .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight, .center])
                }
            }
        }
        capabilityCache[entry.id] = (Date().addingTimeInterval(1), supported)
        if capabilityCache.count > 500 { capabilityCache = capabilityCache.filter { $0.value.0 > Date() } }
        return supported.contains(action)
    }

    @discardableResult
    func perform(_ action: WindowAction, on entry: SelectionEntry) -> WindowActionResult {
        guard let app = NSRunningApplication(processIdentifier: entry.processID), !app.isTerminated,
              entry.bundleIdentifier == nil || app.bundleIdentifier == entry.bundleIdentifier else { return .staleTarget }
        switch action {
        case .quit: return app.terminate() ? .success : .failed
        case .forceQuit: return app.forceTerminate() ? .success : .failed
        case .hide:
            let shouldHide = !app.isHidden
            if PermissionManager.hasAccessibilityAccess {
                let application = AXUIElementCreateApplication(entry.processID)
                let value: CFBoolean = shouldHide ? kCFBooleanTrue : kCFBooleanFalse
                if AXUIElementSetAttributeValue(application, kAXHiddenAttribute as CFString, value) == .success {
                    return .success
                }
            }
            let accepted = shouldHide ? app.hide() : app.unhide()
            return accepted || app.isHidden == shouldHide ? .success : .failed
        case .openApp:
            guard let url = app.bundleURL else { return app.activate() ? .success : .failed }
            return NSWorkspace.shared.open(url) ? .success : .failed
        case .focus:
            app.unhide()
            if let item = entry.window { return windows.focus(item) ? .success : .failed }
            return app.activate() ? .success : .failed
        default: break
        }
        guard PermissionManager.hasAccessibilityAccess else { return .permissionDenied }
        if action == .newWindow {
            guard let menu = newWindowMenu(in: entry.processID) else { return .unsupported }
            app.activate()
            return AXUIElementPerformAction(menu, kAXPressAction as CFString) == .success ? .success : .failed
        }
        guard let item = entry.window, let window = windows.accessibilityWindow(for: item) else { return .staleTarget }
        guard available(action, for: entry) else { return .unsupported }
        let result: AXError
        switch action {
        case .close:
            guard let button = attribute(window, kAXCloseButtonAttribute) else { return .unsupported }
            result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        case .minimize:
            result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, bool(window, kAXMinimizedAttribute) ? kCFBooleanFalse : kCFBooleanTrue)
        case .fullscreen:
            result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, bool(window, "AXFullScreen") ? kCFBooleanFalse : kCFBooleanTrue)
        case .currentSpace:
            return PlatformCapabilities.shared.bringToCurrentSpace(item.id) ? .success : .unsupported
        default:
            let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
            let screen = NSScreen.screens.first { screen in
                let cg = WindowGeometry.accessibilityFrame(screen.frame, desktopTop: desktopTop)
                return cg.contains(CGPoint(x: item.bounds.midX, y: item.bounds.midY))
            } ?? NSScreen.main
            guard let screen else { return .unsupported }
            let visible = WindowGeometry.accessibilityFrame(screen.visibleFrame, desktopTop: desktopTop)
            var frame = WindowGeometry.frame(for: action, current: item.bounds, screen: visible)
            let restoredFrame = action == .maximize ? restoredFrames[entry.id] : nil
            if let restoredFrame { frame = restoredFrame }
            var origin = frame.origin; var size = frame.size
            guard let positionValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else { return .failed }
            let resize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            if resize != .success { return .unsupported }
            if result == .success && action == .maximize {
                if restoredFrame != nil { restoredFrames.removeValue(forKey: entry.id) }
                else { restoredFrames[entry.id] = item.bounds }
            }
        }
        if result == .success { windows.invalidateThumbnails(for: [item.id]); return .success }
        return result == .apiDisabled ? .permissionDenied : .failed
    }
    @discardableResult
    func resize(_ entry: SelectionEntry, to frame: CGRect) -> WindowActionResult {
        guard PermissionManager.hasAccessibilityAccess else { return .permissionDenied }
        guard let item = entry.window, let window = windows.accessibilityWindow(for: item) else { return .staleTarget }
        var point = frame.origin; var size = frame.size
        guard size.width > 0, size.height > 0, let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return .unsupported }
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        if resized == .success && moved == .success { windows.invalidateThumbnails(for: [item.id]); return .success }
        return .unsupported
    }
    private func newWindowMenu(in pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 5 else { return nil }
            let title = attribute(element, kAXTitleAttribute) as? String ?? ""
            let key = attribute(element, "AXMenuItemCmdChar") as? String ?? ""
            let modifiers = attribute(element, "AXMenuItemCmdModifiers") as? Int ?? 0
            let enabled = attribute(element, kAXEnabledAttribute) as? Bool ?? true
            if enabled && (key.lowercased() == "n" && modifiers == 0 || ["New Window", "New Finder Window"].contains(title)) {
                return element
            }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return find(bar as! AXUIElement, depth: 0)
    }
    private func attribute(_ window: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, key as CFString, &value) == .success ? value : nil
    }
    private func bool(_ window: AXUIElement, _ key: String) -> Bool { attribute(window, key) as? Bool ?? false }
}
