import AppKit
import ApplicationServices

struct DockTarget {
    let frame: CGRect
    let processID: pid_t?
    let url: URL?
    let name: String
}

@MainActor
final class DockIntegration {
    var onPreview: ((DockTarget) -> Void)?
    var onReposition: ((CGRect) -> Void)?
    var onDismiss: (() -> Void)?
    var onCommandTab: ((pid_t?) -> Void)?
    var onIndicator: ((DockTarget?) -> Void)?
    var isPointerInsidePreview: (() -> Bool)?
    var settings = FeatureSettings()
    private var task: Task<Void, Never>?
    private var pending: DockTarget?
    private var hoveredAt = Date()
    private var shownID: String?
    private var departedAt: Date?
    private(set) var commandTabFrame: CGRect?
    private var commandTabPID: pid_t?
    private var lastIndicatorUpdate = Date.distantPast
    private var wasCommandTab = false
    private(set) var target: DockTarget?

    func start() {
        stop()
        guard settings.dockEnabled || settings.cmdTabEnabled || settings.indicator else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    func stop() { task?.cancel(); task = nil; shownID = nil; target = nil; commandTabPID = nil; wasCommandTab = false }
    func tick() {
        guard PermissionManager.hasAccessibilityAccess else { return }
        if settings.mediaEnabled { UniversalMediaAdapter.shared.refresh() }
        if settings.cmdTabEnabled {
            let selected = selectedCommandTabApp()
            if let selected {
                if selected != commandTabPID { commandTabPID = selected; onCommandTab?(selected) }
                wasCommandTab = true
            } else if wasCommandTab {
                wasCommandTab = false; commandTabPID = nil; onCommandTab?(nil)
            }
        }
        if settings.indicator, Date().timeIntervalSince(lastIndicatorUpdate) >= 1, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            lastIndicatorUpdate = Date()
            onIndicator?(dockItems().first { $0.processID == pid })
        }
        guard settings.dockEnabled && !wasCommandTab else { return }
        let found = targetAtPointer()
        target = found
        if let found {
            departedAt = nil
            let identity = "\(found.processID ?? 0):\(found.url?.path ?? found.name)"
            if pending?.processID != found.processID || pending?.url != found.url || pending?.name != found.name {
                pending = found; hoveredAt = Date()
            }
            if settings.dockActivation == .hover, identity != shownID,
               (settings.dockOnlyInitialDelay && shownID != nil || Date().timeIntervalSince(hoveredAt) >= settings.dockOpenDelay) {
                shownID = identity; onPreview?(found)
            } else if !settings.anchorDockPreview && identity == shownID { onReposition?(found.frame) }
        } else if isPointerInsidePreview?() != true {
            if departedAt == nil { departedAt = Date() }
            if Date().timeIntervalSince(departedAt!) >= settings.dockDismissDelay {
                pending = nil; shownID = nil; onDismiss?()
            }
        }
    }
    func targetAtPointer() -> DockTarget? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let pointer = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: pointer.x, y: top - pointer.y)
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        var raw: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(cgPoint.x), Float(cgPoint.y), &raw) == .success,
              var element = raw else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == dock.processIdentifier else { return nil }
        for _ in 0..<6 {
            if (value(element, kAXRoleAttribute) as? String ?? "").contains("DockItem") { return dockTarget(element) }
            guard let parent = value(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = parent as! AXUIElement
        }
        return nil
    }
    func activateByClick() -> Bool {
        guard settings.dockEnabled, let target = targetAtPointer() else { return false }
        onPreview?(target); return true
    }
    private func dockRoot() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    private func descendants(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        let children = value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children + children.flatMap { descendants($0, depth: depth + 1) }
    }
    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero; var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }
    func dockItems() -> [DockTarget] {
        guard let root = dockRoot() else { return [] }
        return descendants(root).compactMap(dockTarget)
    }
    private func dockTarget(_ element: AXUIElement) -> DockTarget? {
        let role = value(element, kAXRoleAttribute) as? String ?? ""
        guard role.contains("DockItem"), let frame = frame(element), frame.width > 0 else { return nil }
        let name = value(element, kAXTitleAttribute) as? String ?? ""
        let rawURL = value(element, kAXURLAttribute)
        let url = rawURL as? URL ?? (rawURL as? String).flatMap(URL.init(string:))
        let matching = NSWorkspace.shared.runningApplications.first { app in
            if let url, let bundleURL = app.bundleURL { return bundleURL.standardizedFileURL == url.standardizedFileURL }
            return app.localizedName == name
        }
        return DockTarget(frame: frame, processID: matching?.processIdentifier, url: url, name: name)
    }

    private func selectedCommandTabApp() -> pid_t? {
        guard let root = dockRoot() else { return nil }
        for list in descendants(root) {
            let role = value(list, kAXRoleAttribute) as? String
            guard role == "AXList", let selected = value(list, kAXSelectedChildrenAttribute) as? [AXUIElement],
                  let item = selected.first else { continue }
            let title = value(item, kAXTitleAttribute) as? String ?? ""
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title }) {
                // The regular Dock list has no selected children. Check Command is still down.
                guard CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else { return nil }
                commandTabFrame = frame(list)
                return app.processIdentifier
            }
        }
        return nil
    }
}
