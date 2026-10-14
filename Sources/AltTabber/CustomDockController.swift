import AppKit
import SwiftUI

@MainActor
final class CustomDockController {
    var onPreview: ((CustomDockResolvedItem, CGRect) -> Void)?
    var onPreviewExit: (() -> Void)?
    var onAction: ((WindowAction, CustomDockResolvedItem) -> Void)?
    private var panels: [String: NSPanel] = [:]
    private var activeClickHides = false

    var containsPointer: Bool { panels.values.contains { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) } }

    func stop() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }

    func refresh(settings: AppSettings) {
        guard settings.features.customDockEnabled else { stop(); return }
        activeClickHides = settings.features.customDockActiveClickHides
        guard let primaryScreen = NSScreen.main ?? NSScreen.screens.first else { stop(); return }
        let screens = settings.features.customDockShowOnAllDisplays ? NSScreen.screens : [primaryScreen]
        let wanted = Set(screens.map { String($0.displayID) })
        for key in panels.keys where !wanted.contains(key) { panels.removeValue(forKey: key)?.orderOut(nil) }
        let running = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { CustomDockRunningApp(processID: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                bundlePath: $0.bundleURL?.standardizedFileURL.path, name: $0.localizedName ?? "Application") }
        for screen in screens {
            let key = String(screen.displayID)
            let profile = settings.features.dockProfile(for: key,
                frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            let items = CustomDockContent.resolve(profile: profile, running: running)
            let edge = settings.features.customDockEdge
            let size = CGFloat(settings.features.customDockIconSize)
            let frame = Self.frame(on: screen, edge: edge, iconSize: size,
                itemCount: items.count + (settings.features.customDockFileTrayEnabled ? 1 : 0))
            let panel = panels[key] ?? makePanel()
            let view = CustomDockView(profile: profile, items: items, edge: edge, iconSize: size,
                profiles: settings.features.dockProfiles,
                stagedFiles: settings.features.customDockFileTrayEnabled ? settings.features.customDockStagedFiles : [],
                showFileTray: settings.features.customDockFileTrayEnabled,
                onSelectProfile: { id in settings.features.displayDockProfiles[key] = id },
                onActivate: { [weak self] item in self?.activate(item) },
                onPreview: { [weak self, weak panel] item in
                    guard let panel else { return }; self?.onPreview?(item, panel.frame)
                },
                onHover: { [weak self, weak panel] item in
                    guard settings.features.customDockHoverPreviews, let panel else { return }
                    self?.onPreview?(item, panel.frame)
                },
                onPreviewExit: { [weak self] in self?.onPreviewExit?() },
                onAction: { [weak self] action, item in self?.onAction?(action, item) },
                onPin: { [weak self] item in self?.pin(item, profileID: profile.id, settings: settings) },
                onUnpin: { [weak self] item in self?.unpin(item, profileID: profile.id, settings: settings) },
                onMove: { source, destination in
                    var changed = settings.features.dockProfiles.first(where: { $0.id == profile.id }) ?? .initial
                    changed.movePin(source, before: destination)
                    settings.features.updateDockProfile(changed)
                },
                onStageFile: { url in _ = settings.features.stageDockFile(url) },
                onRemoveStagedFile: { path in settings.features.removeStagedDockFile(path) },
                onSettings: { NotificationCenter.default.post(name: .altTabberShowSettings, object: nil) })
            panel.contentViewController = NSHostingController(rootView: view)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels[key] = panel
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    static func frame(on screen: NSScreen, edge: CustomDockEdge, iconSize: CGFloat, itemCount: Int) -> CGRect {
        frame(in: screen.visibleFrame, edge: edge, iconSize: iconSize, itemCount: itemCount)
    }

    static func frame(in visibleFrame: CGRect, edge: CustomDockEdge, iconSize: CGFloat, itemCount: Int) -> CGRect {
        let slot = iconSize + 12
        let length = CGFloat(itemCount + 2) * slot + 20
        let thickness = slot + 20
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        switch edge {
        case .bottom:
            let width = min(length, bounds.width)
            return CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: thickness)
        case .left:
            let height = min(length, bounds.height)
            return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: thickness, height: height)
        case .right:
            let height = min(length, bounds.height)
            return CGRect(x: bounds.maxX - thickness, y: bounds.midY - height / 2, width: thickness, height: height)
        }
    }

    private func activate(_ item: CustomDockResolvedItem) {
        if let pid = item.processID, let app = NSRunningApplication(processIdentifier: pid) {
            if activeClickHides && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                onAction?(.hide, item); return
            }
            app.unhide(); _ = app.activate(options: [.activateAllWindows]); return
        }
        guard let location = item.location else { return }
        let url = item.kind == .link ? URL(string: location) : URL(fileURLWithPath: location)
        if let url { NSWorkspace.shared.open(url) }
    }

    private func pin(_ item: CustomDockResolvedItem, profileID: String, settings: AppSettings) {
        guard let path = item.location, item.kind == .application else { return }
        var profile = settings.features.dockProfiles.first { $0.id == profileID } ?? .initial
        guard !profile.pins.contains(where: { $0.kind == .application && $0.location == path }) else { return }
        profile.pins.append(.application(URL(fileURLWithPath: path)))
        settings.features.updateDockProfile(profile)
    }

    private func unpin(_ item: CustomDockResolvedItem, profileID: String, settings: AppSettings) {
        var profile = settings.features.dockProfiles.first { $0.id == profileID } ?? .initial
        profile.pins.removeAll { $0.id == item.id }
        settings.features.updateDockProfile(profile)
    }
}

private struct CustomDockView: View {
    let profile: CustomDockProfile
    let items: [CustomDockResolvedItem]
    let edge: CustomDockEdge
    let iconSize: CGFloat
    let profiles: [CustomDockProfile]
    let stagedFiles: [String]
    let showFileTray: Bool
    let onSelectProfile: (String) -> Void
    let onActivate: (CustomDockResolvedItem) -> Void
    let onPreview: (CustomDockResolvedItem) -> Void
    let onHover: (CustomDockResolvedItem) -> Void
    let onPreviewExit: () -> Void
    let onAction: (WindowAction, CustomDockResolvedItem) -> Void
    let onPin: (CustomDockResolvedItem) -> Void
    let onUnpin: (CustomDockResolvedItem) -> Void
    let onMove: (String, String) -> Void
    let onStageFile: (URL) -> Void
    let onRemoveStagedFile: (String) -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView(edge == .bottom ? .horizontal : .vertical) {
            if edge == .bottom { HStack(spacing: 8) { content } }
            else { VStack(spacing: 8) { content } }
        }
        .scrollIndicators(.hidden)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18)))
        .accessibilityLabel("AltTabber Dock, \(profile.name) profile")
    }

    @ViewBuilder private var content: some View {
        Menu {
            ForEach(profiles) { candidate in
                Button(candidate.name) { onSelectProfile(candidate.id) }
            }
        } label: {
            Image(systemName: "square.stack.3d.up")
                .frame(width: iconSize, height: iconSize)
        }
        .help("Switch Dock profile")
        .accessibilityLabel("Switch Dock profile")
        ForEach(items) { item in
            if item.kind == .separator {
                Rectangle().fill(.secondary).frame(width: edge == .bottom ? 1 : iconSize * 0.65,
                                                  height: edge == .bottom ? iconSize * 0.65 : 1)
                    .accessibilityLabel("Dock separator")
                    .draggable(item.id)
                    .dropDestination(for: String.self) { values, _ in
                        guard let source = values.first else { return false }
                        onMove(source, item.id); return true
                    }
            } else {
                Button { onActivate(item) } label: {
                    VStack(spacing: 2) {
                        Image(nsImage: icon(for: item)).resizable().interpolation(.high).scaledToFit()
                            .frame(width: iconSize, height: iconSize - 6)
                            .opacity(item.processID == nil && item.kind == .application ? 0.72 : 1)
                        Circle().fill(NSWorkspace.shared.frontmostApplication?.processIdentifier == item.processID ? Color.accentColor : Color.secondary)
                            .frame(width: 4, height: 4).opacity(item.processID == nil ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel("\(item.title)\(item.processID == nil ? "" : ", running")")
                .onHover { inside in
                    if item.processID != nil {
                        if inside { onHover(item) } else { onPreviewExit() }
                    }
                }
                .contextMenu {
                    if item.processID != nil {
                        Button("Show Windows") { onPreview(item) }
                        Button("Hide or Unhide") { onAction(.hide, item) }
                        Button("Quit") { onAction(.quit, item) }
                    }
                    if item.isPinned { Button("Unpin from Dock") { onUnpin(item) } }
                    else if item.kind == .application { Button("Pin to Dock") { onPin(item) } }
                }
                .draggable(item.id)
                .dropDestination(for: String.self) { values, _ in
                    guard item.isPinned, let source = values.first else { return false }
                    onMove(source, item.id); return true
                }
            }
        }
        if showFileTray {
            Menu {
                if stagedFiles.isEmpty { Text("Drop files here") }
                ForEach(stagedFiles, id: \.self) { path in
                    let url = URL(fileURLWithPath: path)
                    Menu(url.lastPathComponent) {
                        Button("Open") { NSWorkspace.shared.open(url) }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("Remove from Tray") { onRemoveStagedFile(path) }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "tray.full").font(.system(size: iconSize * 0.55))
                    Text("\(stagedFiles.count)").font(.system(size: 9))
                }.frame(width: iconSize, height: iconSize)
            }
            .help("File Tray: drop files here")
            .accessibilityLabel("File Tray, \(stagedFiles.count) items")
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                urls.forEach(onStageFile)
                return true
            }
        }
        Button(action: onSettings) {
            Image(systemName: "gearshape").frame(width: iconSize, height: iconSize)
        }
        .help("AltTabber Settings")
        .accessibilityLabel("AltTabber Settings")
    }

    private func icon(for item: CustomDockResolvedItem) -> NSImage {
        if let path = item.location, item.kind != .link { return NSWorkspace.shared.icon(forFile: path) }
        return NSImage(systemSymbolName: item.kind == .link ? "link" : "app", accessibilityDescription: item.title) ?? NSImage()
    }
}

extension Notification.Name {
    static let altTabberShowSettings = Notification.Name("AltTabber.showSettings")
}
