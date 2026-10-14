import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onRequestAccessibility: () -> Void
    let onRequestScreenRecording: () -> Void
    @State private var selectedTab = "General"
    @State private var search = ""
    @State private var navigationTarget: String?
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var newDockLink = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsCatalog.tabs, id: \.self, selection: $selectedTab) { Text($0).tag($0) }
                .navigationSplitViewColumnWidth(min: 145, ideal: 160, max: 190)
        } detail: {
            VStack {
                TextField("Search settings", text: $search).textFieldStyle(.roundedBorder).padding([.horizontal, .top])
                ScrollViewReader { proxy in
                Form {
                    if !settings.features.onboardingCompleted {
                        Section("Welcome to AltTabber") {
                            Text("Your existing Option-Tab preferences are preserved. Enable Dock previews, Command-Tab, and widgets below when you want them. Online lyrics and update checks require separate opt-ins.").fixedSize(horizontal: false, vertical: true)
                            Toggle("Enable Dock previews", isOn: $settings.features.dockEnabled).id("Enable Dock previews")
                            Toggle("Show AltTabber Dock", isOn: $settings.features.customDockEnabled).id("Show AltTabber Dock")
                            Toggle("Enhance Command-Tab", isOn: $settings.features.cmdTabEnabled).id("Enhance Command-Tab")
                            Button("Finish Setup") { settings.features.onboardingCompleted = true }.id("Finish Setup")
                        }
                    }
                    if search.isEmpty { tabContent(selectedTab) }
                    else {
                        Section("Search Results") {
                            ForEach(SettingsSearch.results(for: search)) { result in
                                Button {
                                    selectedTab = result.tab; search = ""; navigationTarget = result.title
                                    Task { @MainActor in await Task.yield(); proxy.scrollTo(result.title, anchor: .top) }
                                } label: {
                                    HStack { Text(result.title); Spacer(); Text(result.tab).foregroundStyle(.secondary); Image(systemName: "arrow.right") }
                                }.buttonStyle(.plain)
                            }
                            if SettingsSearch.results(for: search).isEmpty { Text("No matching settings") }
                        }
                    }
                }.formStyle(.grouped)
                .onChange(of: navigationTarget) { _, target in if let target { proxy.scrollTo(target, anchor: .top) } }
                }
            }
        }.frame(minWidth: 620, minHeight: 480)
        .alert("Couldn’t Update Setting", isPresented: $isShowingError) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unknown error") }.id("OK")
    }
    private func matches(_ title: String) -> Bool { title.localizedCaseInsensitiveContains(search) }
    @ViewBuilder private func preferenceRows(_ toggles: [BooleanSetting], _ numbers: [NumberSetting], _ texts: [TextSetting]) -> some View {
        ForEach(toggles) { item in
            Toggle(item.title, isOn: Binding(get: { settings.features[keyPath: item.key] }, set: { settings.features[keyPath: item.key] = $0 }))
                .id(item.title)
                .disabled(item.title == "Current Space only" && !PlatformCapabilities.shared.supportsSpaces)
        }
        ForEach(numbers) { item in
            VStack(alignment: .leading) {
                HStack { Text(item.title); Spacer(); Text(settings.features[keyPath: item.key], format: .number.precision(.fractionLength(0...2))).foregroundStyle(.secondary) }
                Slider(value: Binding(get: { settings.features[keyPath: item.key] }, set: { settings.features[keyPath: item.key] = $0 }), in: item.range)
            }.id(item.title)
        }
        ForEach(texts) { item in
            VStack(alignment: .leading) {
                Text(item.title).font(.caption)
                TextEditor(text: Binding(get: { settings.features[keyPath: item.key] }, set: { settings.features[keyPath: item.key] = $0 })).frame(height: 70)
            }.id(item.title)
        }
    }
    @ViewBuilder private func tabContent(_ tab: String) -> some View {
        Section(tab) { preferenceRows(SettingsCatalog.toggles(tab), SettingsCatalog.numbers(tab), SettingsCatalog.texts(tab)) }
        switch tab {
        case "General":
            Section("Application") {
                Toggle("Launch at Login", isOn: Binding(get: { settings.launchAtLogin }, set: { value in attempt { try settings.setLaunchAtLogin(value) } })).id("Launch at Login")
                Picker("Update channel", selection: $settings.features.updateChannel) { ForEach(UpdateChannel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Button("Check for Updates…") { NotificationCenter.default.post(name: .altTabberCheckUpdates, object: nil) }.id("Check for Updates…")
                Text("Unconfigured update feeds open the AltTabber releases page. No automatic network checks occur until enabled.").font(.caption)
            }
            Section("Backup and Diagnostics") {
                Button("Export Settings…") { exportSettings() }.id("Export Settings…")
                Button("Import Settings…") { importSettings() }.id("Import Settings…")
                Button("Export Local Diagnostics…") { exportDiagnostics() }.id("Export Local Diagnostics…")
                Text("Backups preserve preferences, not macOS permission grants or login registration.").font(.caption)
            }
        case "Window Switcher":
            Section("Selection") {
                Picker("Sort order", selection: $settings.features.sortOrder) { ForEach(WindowSortOrder.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Stepper("Search fuzziness: \(settings.features.searchFuzziness)", value: $settings.features.searchFuzziness, in: 1...5)
                Stepper("Compact list threshold (0 disables): \(settings.features.compactThreshold)", value: $settings.features.compactThreshold, in: 0...100)
                Button("Save current window order") { NotificationCenter.default.post(name: .altTabberSaveOrder, object: nil) }.id("Save current window order")
            }
            Section("Shortcuts") {
                ShortcutRecorder(title: "Primary", shortcut: $settings.features.primaryShortcut)
                Toggle("Enable alternate shortcut (active app)", isOn: $settings.features.alternateShortcut.enabled).id("Enable alternate shortcut (active app)")
                ShortcutRecorder(title: "Alternate", shortcut: $settings.features.alternateShortcut)
                KeyRecorder(title: "Backward cycling key", code: $settings.features.backwardKey).id("Backward cycling key")
                KeyRecorder(title: "Selection key", code: $settings.features.selectionKey).id("Selection key")
                KeyRecorder(title: "Search key", code: $settings.features.searchKey).id("Search key")
                KeyRecorder(title: "Close key (Command)", code: $settings.features.closeKey).id("Close key (Command)")
                KeyRecorder(title: "Minimize key (Command)", code: $settings.features.minimizeKey).id("Minimize key (Command)")
                KeyRecorder(title: "Quit key (Command)", code: $settings.features.quitKey).id("Quit key (Command)")
                Picker("Large preview during Option-Tab", selection: $settings.features.largePreviewTrigger) {
                    ForEach(LargePreviewTrigger.allCases) { trigger in Text(trigger.title).tag(trigger) }
                }.id("Large preview during Option-Tab")
                KeyRecorder(title: "Large preview key (Command)", code: $settings.features.largePreviewKey).id("Large preview key (Command)")
                actionPicker("Close shortcut action", value: $settings.features.closeKeyAction)
                actionPicker("Minimize shortcut action", value: $settings.features.minimizeKeyAction)
                actionPicker("Quit shortcut action", value: $settings.features.quitKeyAction)
                Text("While holding Option in the switcher, tap the selected large-preview key. Releasing Option still selects the window. Control needs Accessibility access; § also works through a temporary switcher shortcut. Command-P remains available while searching and can be changed above. Backward cycling uses Shift plus the primary shortcut.").font(.caption)
                ForEach(settings.features.shortcutConflicts, id: \.self) { conflict in
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Shortcut status", value: settings.shortcutStatus.title)
            }
        case "Dock Previews":
            SurfaceStyleEditor(style: $settings.features.dockStyle)
            Section("Dock Interaction") {
                Picker("Preview activation", selection: $settings.features.dockActivation) { ForEach(DockActivation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Activation modifier", selection: $settings.features.dockModifier) { ForEach(ShortcutModifier.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Stepper("Compact list threshold: \(settings.features.dockCompactThreshold)", value: $settings.features.dockCompactThreshold, in: 0...100)
                HexColorPicker(title: "Indicator color", hex: $settings.features.indicatorHex).id("Indicator color")
                Picker("Sort order", selection: $settings.features.dockSortOrder) { ForEach(WindowSortOrder.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Dock lock override", selection: $settings.features.dockLockModifier) { ForEach(ShortcutModifier.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Indicator style", selection: $settings.features.indicatorStyle) { ForEach(IndicatorStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                displayPicker("Dock lock display", value: $settings.features.dockLockDisplay)
            }
        case "Custom Dock":
            Section("Placement") {
                Picker("Edge", selection: $settings.features.customDockEdge) {
                    ForEach(CustomDockEdge.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.id("Edge")
                Slider(value: $settings.features.customDockIconSize, in: 28...96, step: 2) {
                    Text("Icon size")
                }.id("Icon size")
                Text("AltTabber Dock sits inside the visible screen area. The macOS Dock stays available while this feature is being built.").font(.caption)
            }
            Section("Profiles") {
                Picker("Active profile and AppSense fallback", selection: $settings.features.activeDockProfileID) {
                    ForEach(settings.features.dockProfiles) { profile in Text(profile.name).tag(profile.id) }
                }.id("Active profile")
                TextField("Profile name", text: Binding(get: { settings.features.selectedDockProfile.name }, set: { name in
                    var profile = settings.features.selectedDockProfile; profile.name = name
                    settings.features.updateDockProfile(profile)
                })).id("Profile name")
                Toggle("Show unpinned running apps", isOn: Binding(get: { settings.features.selectedDockProfile.showRunningApps }, set: { value in
                    var profile = settings.features.selectedDockProfile; profile.showRunningApps = value
                    settings.features.updateDockProfile(profile)
                })).id("Show unpinned running apps")
                TextField("Linked app bundle IDs (comma-separated)", text: Binding(get: {
                    settings.features.selectedDockProfile.linkedAppBundleIDs.joined(separator: ", ")
                }, set: { value in
                    var profile = settings.features.selectedDockProfile
                    profile.linkedAppBundleIDs = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    settings.features.updateDockProfile(profile)
                })).id("Linked app bundle IDs (comma-separated)")
                Text("When AppSense is enabled, focusing a linked app selects this profile. The active profile is used when no link matches. A display assignment takes priority.").font(.caption)
                HStack {
                    Button("New Profile") {
                        let profile = CustomDockProfile(id: UUID().uuidString,
                            name: "Profile \(settings.features.dockProfiles.count + 1)", pins: [], showRunningApps: true)
                        settings.features.dockProfiles.append(profile)
                        settings.features.activeDockProfileID = profile.id
                    }.id("New Profile")
                    Button("Delete Profile") { settings.features.removeDockProfile(settings.features.activeDockProfileID) }
                        .disabled(settings.features.dockProfiles.count <= 1).id("Delete Profile")
                }
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    Picker("\(screen.localizedName) profile", selection: Binding(get: {
                        settings.features.displayDockProfiles[String(screen.displayID)] ?? ""
                    }, set: { value in
                        if value.isEmpty { settings.features.displayDockProfiles.removeValue(forKey: String(screen.displayID)) }
                        else { settings.features.displayDockProfiles[String(screen.displayID)] = value }
                    })) {
                        Text("Follow active profile / AppSense").tag("")
                        ForEach(settings.features.dockProfiles) { profile in Text(profile.name).tag(profile.id) }
                    }
                }
            }
            Section("Pinned Items") {
                Button("Add Applications…") { addDockApplications() }.id("Add Applications…")
                Button("Import System Dock Apps") { NotificationCenter.default.post(name: .altTabberImportDockApps, object: nil) }
                    .disabled(!PermissionManager.hasAccessibilityAccess).id("Import System Dock Apps")
                Button("Add Files or Folders…") { addDockFiles() }.id("Add Files or Folders…")
                HStack {
                    TextField("https://example.com", text: $newDockLink)
                    Button("Add Link") { addDockLink() }.disabled(URL(string: newDockLink)?.scheme?.hasPrefix("http") != true)
                }.id("Add Link")
                Button("Add Separator") {
                    var profile = settings.features.selectedDockProfile
                    profile.pins.append(CustomDockPin(kind: .separator, title: "Separator", location: ""))
                    settings.features.updateDockProfile(profile)
                }.id("Add Separator")
                ForEach(settings.features.selectedDockProfile.pins) { pin in
                    HStack {
                        Text(pin.title)
                        Spacer()
                        Button("Remove") {
                            var profile = settings.features.selectedDockProfile
                            profile.pins.removeAll { $0.id == pin.id }
                            settings.features.updateDockProfile(profile)
                        }
                    }
                }
                Text("Drag pinned icons in the AltTabber Dock to reorder them. Running app icons can be pinned from their context menu.").font(.caption)
            }
            Section("File Tray") {
                Button("Add Files to Tray…") { addFilesToDockTray() }.id("Add Files to Tray…")
                Text("\(settings.features.customDockStagedFiles.count) staged items. Drop files on the tray icon to add them, or use its menu to open and remove them.").font(.caption)
                Button("Clear File Tray") { settings.features.customDockStagedFiles = [] }
                    .disabled(settings.features.customDockStagedFiles.isEmpty).id("Clear File Tray")
            }
        case "Command-Tab":
            SurfaceStyleEditor(style: $settings.features.commandTabStyle)
            Section("Navigation") {
                Picker("Sort order", selection: $settings.features.commandTabSortOrder) { ForEach(WindowSortOrder.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                KeyRecorder(title: "Forward window key", code: $settings.features.commandTabForwardKey).id("Forward window key")
                KeyRecorder(title: "Backward window key", code: $settings.features.commandTabBackwardKey).id("Backward window key")
                Text("Hold Command-Tab to see the highlighted app’s windows. Command-A cycles forward; Command-` cycles backward. Return or a click selects a window.")
                Stepper("Compact list threshold: \(settings.features.cmdTabCompactThreshold)", value: $settings.features.cmdTabCompactThreshold, in: 0...100)
            }
        case "Appearance":
            SurfaceStyleEditor(style: $settings.features.switcherStyle)
            Section("Layout") {
                Picker("Layout", selection: $settings.layout) { ForEach(SwitcherLayout.allCases) { Text($0.title).tag($0) } }
                Stepper("Grid columns: \(settings.gridColumns)", value: $settings.gridColumns, in: 2...6)
                Picker("Preview size", selection: $settings.previewSize) { ForEach(PreviewSize.allCases) { Text($0.title).tag($0) } }
                Toggle("Show window titles", isOn: $settings.showWindowTitles).id("Show window titles")
                Picker("Material", selection: $settings.features.material) { ForEach(PreviewMaterial.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Display placement", selection: $settings.features.placement) { ForEach(PanelPlacement.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                displayPicker("Pinned display", value: $settings.features.pinnedDisplay)
            }
        case "Capture":
            Section("Streaming") {
                Stepper("Dock frame rate: \(settings.features.dockLiveFrameRate) fps", value: $settings.features.dockLiveFrameRate, in: 1...30)
                Stepper("Switcher frame rate: \(settings.features.liveFrameRate) fps", value: $settings.features.liveFrameRate, in: 1...30)
                LabeledContent("Preview status", value: settings.previewStatus.title)
                Text("Streams stop when panels close, after any configured keep-alive. Hidden and minimized windows use cached images or icons.").font(.caption)
            }
        case "Gestures":
            Section("Actions") {
                actionPicker("Middle click", value: $settings.features.middleClickAction)
                actionPicker("Swipe up / away from Dock", value: $settings.features.swipeUpAction)
                actionPicker("Swipe down / toward Dock", value: $settings.features.swipeDownAction)
                Stepper("Global swipe fingers: \(settings.features.swipeFingers)", value: $settings.features.swipeFingers, in: 3...4)
            }
        case "Widgets":
            Section("Folder Sorting") {
                Picker("Default sort", selection: $settings.features.folderSort) { ForEach(FolderSort.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Text("Calendar requests access from its widget. Music and Spotify request Automation access when controls are used. Folder previews offer Choose Folder if access is denied.").font(.caption)
            }
        case "Automation":
            Section("AppleScript and CLI") {
                Text("tell application \"AltTabber\" to perform command \"list-windows\"").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("The bundled alttabber CLI accepts a command followed by a JSON arguments object. See docs/automation.md for commands and examples.")
                Text(PlatformCapabilities.shared.explanation).font(.caption)
            }
        case "Permissions":
            Section("macOS Access") {
                permissionRow("Accessibility", granted: PermissionManager.hasAccessibilityAccess, action: onRequestAccessibility)
                permissionRow("Screen Recording", granted: PermissionManager.hasScreenRecordingAccess, action: onRequestScreenRecording)
                Text(PlatformCapabilities.shared.explanation)
                Text(UniversalMediaAdapter.shared.explanation)
                Text("If macOS does not recognize a permission change, quit and reopen AltTabber.").font(.caption)
            }
        default: EmptyView()
        }
    }
    private func displayPicker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            Text("Choose display").tag("")
            ForEach(NSScreen.screens, id: \.displayID) { Text($0.localizedName).tag(String($0.displayID)) }
        }
    }
    private func actionPicker(_ title: String, value: Binding<WindowAction>) -> some View {
        Picker(title, selection: value) { ForEach(WindowAction.allCases) { Text($0.title).tag($0) } }
    }
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack { Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"); Spacer(); if !granted { Button("Grant…", action: action) } }.id(title)
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription; isShowingError = true }
    }
    private func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "AltTabber-settings.json"
        if panel.runModal() == .OK, let url = panel.url { attempt { try settings.exportBackup().write(to: url, options: .atomic) } }
    }
    private func addDockApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose applications to pin in the active AltTabber Dock profile."
        guard panel.runModal() == .OK else { return }
        var profile = settings.features.selectedDockProfile
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !profile.pins.contains(where: { $0.kind == .application && $0.location == path }) {
                profile.pins.append(.application(url))
            }
        }
        settings.features.updateDockProfile(profile)
    }
    private func addDockFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to pin in the active AltTabber Dock profile."
        guard panel.runModal() == .OK else { return }
        var profile = settings.features.selectedDockProfile
        for url in panel.urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let pin = CustomDockPin.file(url, isDirectory: isDirectory)
            if !profile.pins.contains(where: { $0.kind == pin.kind && $0.location == pin.location }) {
                profile.pins.append(pin)
            }
        }
        settings.features.updateDockProfile(profile)
    }
    private func addDockLink() {
        guard let url = URL(string: newDockLink), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        var profile = settings.features.selectedDockProfile
        if !profile.pins.contains(where: { $0.kind == .link && $0.location == url.absoluteString }) {
            profile.pins.append(.link(url))
            settings.features.updateDockProfile(profile)
        }
        newDockLink = ""
    }
    private func addFilesToDockTray() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose files to stage in the AltTabber Dock tray."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { _ = settings.features.stageDockFile(url) }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { attempt { try settings.importBackup(Data(contentsOf: url)) } }
    }
    private func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "AltTabber-diagnostics.txt"
        let report = "AltTabber diagnostics\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nAccessibility: \(PermissionManager.hasAccessibilityAccess)\nScreen capture: \(PermissionManager.hasScreenRecordingAccess)\nShortcut: \(settings.shortcutStatus.title)\nPreview: \(settings.previewStatus.title)\n\(PlatformCapabilities.shared.explanation)\n\(DiagnosticLog.shared.text)\n"
        if panel.runModal() == .OK, let url = panel.url { attempt { try report.write(to: url, atomically: true, encoding: .utf8) } }
    }
}
extension Notification.Name {
    static let altTabberCheckUpdates = Notification.Name("AltTabber.checkUpdates")
    static let altTabberSaveOrder = Notification.Name("AltTabber.saveOrder")
    static let altTabberImportDockApps = Notification.Name("AltTabber.importDockApps")
}

struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut
    var body: some View {
        HStack {
            KeyRecorder(title: title, code: $shortcut.keyCode)
            Picker("Modifier", selection: $shortcut.modifier) { ForEach(ShortcutModifier.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.frame(width: 130)
        }
    }
}
struct KeyRecorder: NSViewRepresentable {
    let title: String
    @Binding var code: Int
    func makeNSView(context: Context) -> KeyCaptureButton {
        let view = KeyCaptureButton(title: title, target: nil, action: nil)
        view.bezelStyle = .rounded; return view
    }
    func updateNSView(_ view: KeyCaptureButton, context: Context) {
        view.title = "\(title): \(KeyLabels.name(code)) (click to record)"
        view.capture = { code = $0 }
    }
}
final class KeyCaptureButton: NSButton {
    var capture: ((Int) -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { recording = true; title = "Press a key…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false
        if event.keyCode != 53 { capture?(Int(event.keyCode)) }
        window?.makeFirstResponder(nil)
    }
}

@MainActor
enum KeyLabels {
    static func name(_ code: Int) -> String {
        let special = [48: "Tab", 36: "Return", 49: "Space", 53: "Escape", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let value = special[code] { return value }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(clamping: code), keyDown: true),
              let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !characters.isEmpty else { return "Unknown key" }
        return characters.uppercased()
    }
}
