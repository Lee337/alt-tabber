import XCTest
@testable import AltTabber

@MainActor
final class FeatureTests: XCTestCase {
    private func window(_ id: UInt32, title: String = "Document", minimized: Bool = false, spaces: [UInt64]? = nil) -> SelectionEntry {
        var w = WindowItem(id: id, processID: 10, appName: "Editor", title: title,
            bounds: CGRect(x: 0, y: 0, width: 600, height: 400), appIcon: NSImage(), thumbnail: nil)
        w.isMinimized = minimized; w.spaceIDs = spaces
        return .window(w)
    }
    func testWindowlessIdentityCannotCollideWithWindowID() {
        let app = SelectionEntry.application(ApplicationItem(processID: 10, name: "Editor", bundleIdentifier: nil, icon: NSImage()))
        XCTAssertNotEqual(app.id, window(10).id)
        XCTAssertNil(app.window)
    }
    func testUnknownSpaceMembershipIsExcludedRatherThanAssumedCurrent() {
        var settings = FeatureSettings(); settings.currentSpaceOnly = true
        let query = WindowQuery(currentSpaces: [7])
        let results = query.apply(to: [window(1), window(2, spaces: [7]), window(3, spaces: [8])], settings: settings)
        XCTAssertEqual(results.compactMap { $0.window?.id }, [2])
    }
    func testSurfaceFiltersAreIndependent() {
        var settings = FeatureSettings(); settings.includeHidden = false; settings.dockIncludeHidden = true
        let entries = [window(1, minimized: true), window(2)]
        XCTAssertEqual(WindowQuery().apply(to: entries, settings: settings).count, 1)
        XCTAssertEqual(WindowQuery(surface: .dock).apply(to: entries, settings: settings).count, 2)
    }
    func testQueryAppliesExclusionsAndSearchTogether() {
        var settings = FeatureSettings(); settings.excludedTitles = "Secret"
        let query = WindowQuery(text: "report")
        let entries = [window(1, title: "Report"), window(2, title: "Secret Report"), window(3, title: "Notes")]
        XCTAssertEqual(query.apply(to: entries, settings: settings).compactMap { $0.window?.id }, [1])
    }
    func testSearchIsCaseAndDiacriticInsensitiveAndSupportsMultipleWords() {
        XCTAssertTrue(FuzzySearch.matches("resume edit", in: "Editor Résumé", fuzziness: 1))
        XCTAssertFalse(FuzzySearch.matches("missing", in: "Editor Résumé", fuzziness: 5))
        XCTAssertTrue(FuzzySearch.matches("rpt", in: "Report", fuzziness: 3))
        XCTAssertFalse(FuzzySearch.matches("rpt", in: "Report", fuzziness: 1))
    }
    func testSelectionSurvivesFilteringAndWindowRemoval() {
        let model = SwitcherModel(); model.replaceEntries([window(1), window(2), window(3)])
        model.select(1)
        model.replaceEntries([window(3), window(2)], preserveSelection: true)
        XCTAssertEqual(model.selectedWindow?.id, 2)
        model.replaceEntries([window(3)], preserveSelection: true)
        XCTAssertEqual(model.selectedWindow?.id, 3)
        model.searchText = "Nothing matches"
        XCTAssertNil(model.selectedEntry)
    }
    func testThumbnailsDoNotTriggerSelectionCallbackOrLoseSearch() {
        let model = SwitcherModel(); model.replaceEntries([window(1, title: "Report"), window(2, title: "Notes")])
        model.searchText = "report"
        var callbacks = 0; model.onSelectionChanged = { callbacks += 1 }
        model.setThumbnail(NSImage(), for: 1)
        XCTAssertEqual(callbacks, 0); XCTAssertEqual(model.entries.count, 1)
        XCTAssertNotNil(model.selectedWindow?.thumbnail)
    }
    func testWindowlessCommitUsesEntryCallback() {
        let model = SwitcherModel()
        let app = SelectionEntry.application(ApplicationItem(processID: 22, name: "Empty", bundleIdentifier: nil, icon: NSImage()))
        model.replaceEntries([app]); var committed: String?
        model.onEntryCommit = { committed = $0.id }; model.commit()
        XCTAssertEqual(committed, app.id)
    }
    func testPersistentOrderIgnoresDuplicateAndMissingEntries() {
        var settings = FeatureSettings(); settings.sortOrder = .persistent
        settings.persistedOrder = [window(2).id, window(2).id, "stale"]
        let results = WindowQuery().apply(to: [window(1), window(2)], settings: settings)
        XCTAssertEqual(results.first?.window?.id, 2)
    }
    func testGroupingKeepsEveryWindowAndMakesAppEntriesAdjacent() {
        let first = window(1)
        var browser = WindowItem(id: 2, processID: 11, appName: "Browser", title: "Page",
            bounds: CGRect(x: 0, y: 0, width: 600, height: 400), appIcon: NSImage(), thumbnail: nil)
        browser.lastUsedAt = Date()
        let middle = SelectionEntry.window(browser)
        let last = window(3)
        var settings = FeatureSettings(); settings.sortOrder = .persistent
        settings.persistedOrder = [first.id, middle.id, last.id]
        settings.groupedApps = "Editor"
        let result = WindowQuery().apply(to: [first, middle, last], settings: settings)
        XCTAssertEqual(result.compactMap { $0.window?.id }, [1, 3, 2])
    }
    func testSettingsMigrationKeepsLegacyAppearanceAndDisablesNewFeatures() throws {
        let name = "AltTabberTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("horizontal", forKey: "switcherLayout"); defaults.set(6, forKey: "gridColumns")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.layout, .horizontal); XCTAssertEqual(settings.gridColumns, 6)
        XCTAssertFalse(settings.features.dockEnabled); XCTAssertFalse(settings.features.mediaEnabled)
        XCTAssertFalse(settings.features.lyricsEnabled); XCTAssertFalse(settings.features.updatesEnabled)
        XCTAssertEqual(settings.features.cacheSeconds, 600)
        let migrated = try FeatureSettings.decode(Data("{\"schemaVersion\":1,\"dockEnabled\":true}".utf8))
        XCTAssertTrue(migrated.dockEnabled); XCTAssertFalse(migrated.lyricsEnabled)
        XCTAssertFalse(migrated.customDockEnabled)
        XCTAssertEqual(migrated.dockProfiles.map(\.id), ["default"])
    }
    func testCustomDockProfilesMergePinnedAndRunningAppsWithoutDuplicates() {
        let appURL = URL(fileURLWithPath: "/Applications/Editor.app")
        var profile = CustomDockProfile.initial
        let pin = CustomDockPin.application(appURL)
        profile.pins = [pin]
        let apps = [
            CustomDockRunningApp(processID: 10, bundleIdentifier: "example.editor", bundlePath: appURL.path, name: "Editor"),
            CustomDockRunningApp(processID: 11, bundleIdentifier: "example.browser", bundlePath: "/Applications/Browser.app", name: "Browser")]
        let entries = CustomDockContent.resolve(profile: profile, running: apps)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.id, pin.id)
        XCTAssertEqual(entries.first?.processID, 10)
        XCTAssertEqual(entries.last?.id, "running:11")
        profile.showRunningApps = false
        XCTAssertEqual(CustomDockContent.resolve(profile: profile, running: apps).map(\.id), [pin.id])
    }
    func testCustomDockProfileReorderAndFallback() throws {
        var profile = CustomDockProfile.initial
        profile.pins = [CustomDockPin.application(URL(fileURLWithPath: "/Applications/A.app")),
                        CustomDockPin.application(URL(fileURLWithPath: "/Applications/B.app")),
                        CustomDockPin.application(URL(fileURLWithPath: "/Applications/C.app"))]
        let ids = profile.pins.map(\.id)
        profile.movePin(ids[2], before: ids[0])
        XCTAssertEqual(profile.pins.map(\.id), [ids[2], ids[0], ids[1]])
        profile.id = "work"
        var features = FeatureSettings()
        features.dockProfiles.append(profile)
        features.activeDockProfileID = "missing"
        features.displayDockProfiles = ["display": "missing"]
        features.normalize()
        XCTAssertEqual(features.activeDockProfileID, "default")
        XCTAssertTrue(features.displayDockProfiles.isEmpty)
        XCTAssertEqual(features.dockProfile(for: "display").id, "default")
        features.activeDockProfileID = "work"
        features.removeDockProfile("work")
        XCTAssertEqual(features.activeDockProfileID, "default")
    }
    func testCustomDockPinTypesAndDisplayGeometry() {
        let folder = CustomDockPin.file(URL(fileURLWithPath: "/tmp/Folder"), isDirectory: true)
        let file = CustomDockPin.file(URL(fileURLWithPath: "/tmp/Report.pdf"), isDirectory: false)
        let link = CustomDockPin.link(URL(string: "https://example.com/path")!)
        XCTAssertEqual([folder.kind, file.kind, link.kind], [.folder, .file, .link])
        XCTAssertEqual(link.location, "https://example.com/path")
        let display = CGRect(x: -1200, y: -400, width: 1200, height: 800)
        let bottom = CustomDockController.frame(in: display, edge: .bottom, iconSize: 48, itemCount: 30)
        let left = CustomDockController.frame(in: display, edge: .left, iconSize: 48, itemCount: 30)
        XCTAssertGreaterThanOrEqual(bottom.minX, display.minX)
        XCTAssertLessThanOrEqual(bottom.maxX, display.maxX)
        XCTAssertGreaterThanOrEqual(left.minY, display.minY)
        XCTAssertLessThanOrEqual(left.maxY, display.maxY)
    }
    func testCustomDockAppSenseHonorsDisplayOverrideAndFallback() throws {
        var settings = FeatureSettings()
        settings.customDockAppSenseEnabled = true
        settings.dockProfiles.append(CustomDockProfile(id: "writing", name: "Writing", pins: [],
            showRunningApps: false, linkedAppBundleIDs: ["com.example.Editor"]))
        XCTAssertEqual(settings.dockProfile(for: "one", frontmostBundleID: "com.example.editor").id, "writing")
        XCTAssertEqual(settings.dockProfile(for: "one", frontmostBundleID: "com.example.browser").id, "default")
        settings.displayDockProfiles["one"] = "default"
        XCTAssertEqual(settings.dockProfile(for: "one", frontmostBundleID: "com.example.editor").id, "default")
        let legacy = Data("{\"id\":\"older\",\"name\":\"Older\",\"pins\":[],\"showRunningApps\":true}".utf8)
        XCTAssertTrue(try JSONDecoder().decode(CustomDockProfile.self, from: legacy).linkedAppBundleIDs.isEmpty)
    }
    func testSystemDockImportPreservesOrderAndSkipsDuplicateApps() {
        var profile = CustomDockProfile.initial
        let editor = URL(fileURLWithPath: "/Applications/Editor.app")
        let browser = URL(fileURLWithPath: "/Applications/Browser.app")
        let file = URL(fileURLWithPath: "/tmp/notes.txt")
        XCTAssertEqual(profile.importApplications([editor, file, browser, editor]), 2)
        XCTAssertEqual(profile.pins.map(\.title), ["Editor", "Browser"])
        XCTAssertEqual(profile.importApplications([browser]), 0)
    }
    func testCustomDockSettingsSurviveBackupAndOldBackupsRemainDisabled() throws {
        let domain = "AltTabberDockTests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        var profile = CustomDockProfile(id: "work", name: "Work", pins: [], showRunningApps: false,
            linkedAppBundleIDs: ["com.example.editor"])
        profile.importApplications([URL(fileURLWithPath: "/Applications/Editor.app")])
        settings.features.dockProfiles.append(profile)
        settings.features.activeDockProfileID = "work"
        settings.features.customDockEnabled = true
        let backup = try settings.exportBackup()
        settings.features = FeatureSettings()
        try settings.importBackup(backup)
        XCTAssertTrue(settings.features.customDockEnabled)
        XCTAssertEqual(settings.features.selectedDockProfile.pins.count, 1)
        XCTAssertEqual(settings.features.selectedDockProfile.linkedAppBundleIDs, ["com.example.editor"])
        XCTAssertFalse(try FeatureSettings.decode(Data("{\"schemaVersion\":1}".utf8)).customDockEnabled)
    }
    func testFileTrayStagingDeduplicatesAndSurvivesSettingsEncoding() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = FeatureSettings()
        XCTAssertTrue(settings.stageDockFile(file))
        XCTAssertFalse(settings.stageDockFile(file))
        XCTAssertEqual(settings.customDockStagedFiles, [file.standardizedFileURL.path])
        let restored = try FeatureSettings.decode(JSONEncoder().encode(settings))
        XCTAssertEqual(restored.customDockStagedFiles, settings.customDockStagedFiles)
        settings.removeStagedDockFile(file.path)
        XCTAssertTrue(settings.customDockStagedFiles.isEmpty)
    }
    func testBackupRoundTripAndInvalidImportAreAtomic() throws {
        let name = "AltTabberTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.layout = .list; settings.features.dockEnabled = true; settings.features.excludedTitles = "Secret"
        let backup = try settings.exportBackup()
        settings.layout = .grid; settings.features.dockEnabled = false
        try settings.importBackup(backup)
        XCTAssertEqual(settings.layout, .list); XCTAssertTrue(settings.features.dockEnabled)
        XCTAssertThrowsError(try settings.importBackup(Data("{\"version\":1}".utf8)))
        XCTAssertEqual(settings.layout, .list); XCTAssertEqual(settings.features.excludedTitles, "Secret")
        XCTAssertThrowsError(try FeatureSettings.decode(Data("{\"schemaVersion\":99}".utf8)))
    }
    func testGeometryHandlesNegativeDisplayOriginsAndQuarters() {
        let screen = CGRect(x: -1200, y: -400, width: 1200, height: 800)
        let frame = WindowGeometry.frame(for: .bottomRight, current: .zero, screen: screen)
        XCTAssertEqual(frame, CGRect(x: -600, y: 0, width: 600, height: 400))
        XCTAssertEqual(WindowGeometry.accessibilityFrame(CGRect(x: -1200, y: 200, width: 800, height: 600), desktopTop: 1000), CGRect(x: -1200, y: 200, width: 800, height: 600))
    }
    func testDockLockAllowsModifierOverrideAndSharedDisplayEdges() {
        let frames = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let point = CGPoint(x: 1500, y: 799)
        XCTAssertEqual(DockLockGeometry.constrained(point, screens: frames, lockedIndex: 0, orientation: "bottom", override: false).y, 796)
        XCTAssertEqual(DockLockGeometry.constrained(point, screens: frames, lockedIndex: 0, orientation: "bottom", override: true), point)
        XCTAssertEqual(DockLockGeometry.constrained(CGPoint(x: 1001, y: 400), screens: frames, lockedIndex: 0, orientation: "left", override: false), CGPoint(x: 1001, y: 400))
    }
    func testSwipeOpensCyclesAndCommitsOnlyOnce() {
        var detector = SwipeDetector()
        func points(_ x: Double) -> [SwipePoint] { (0..<3).map { SwipePoint(id: $0, x: x, y: 0) } }
        XCTAssertNil(detector.update(points(0), fingers: 3))
        XCTAssertEqual(detector.update(points(0.1), fingers: 3), .open)
        XCTAssertEqual(detector.update(points(0.2), fingers: 3), .forward)
        XCTAssertEqual(detector.update([], fingers: 3), .commit)
        XCTAssertNil(detector.update([], fingers: 3))
    }
    func testFolderSortUsesStableTieBreakingAndEmptyDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(try FolderListing.read(root, hidden: false, sort: .name, descending: false).isEmpty)
        try Data().write(to: root.appendingPathComponent(".hidden")); try Data().write(to: root.appendingPathComponent("Visible"))
        XCTAssertEqual(try FolderListing.read(root, hidden: false, sort: .name, descending: false).map(\.name), ["Visible"])
        XCTAssertEqual(try FolderListing.read(root, hidden: true, sort: .name, descending: false).count, 2)
    }
    func testLyricsParsingDoesNotInventTimesForPlainLyrics() {
        XCTAssertEqual(LyricsParser.parse("[00:12.50]Hello\n[00:13.00]World\n[ar:Artist]", synchronized: true).map(\.time), [12.5, 13])
        XCTAssertEqual(LyricsParser.parse("Hello\nWorld", synchronized: false).map(\.time), [nil, nil])
    }
    func testScriptJSONRepresentsUnknownSpacesAsNullOrAbsent() throws {
        let value = try XCTUnwrap(window(1).window)
        let data = Data(try ScriptJSON.encode(ScriptWindow(value)).utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["spaceIDs"]); XCTAssertEqual(object["id"] as? Int, 1)
    }
    func testAppleScriptWindowVerbsResolveToSharedActions() throws {
        let focus = try ScriptingAlias.resolve(name: "focus window", direct: "123", json: "{}")
        XCTAssertEqual(focus.0, "window-action")
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(focus.1.utf8)) as? [String: Any])
        XCTAssertEqual(arguments["window"] as? Int, 123)
        XCTAssertEqual(arguments["action"] as? String, "focus")
        let windows = try ScriptingAlias.resolve(name: "get windows", direct: nil, json: "{\"bundle\":\"com.apple.finder\"}")
        XCTAssertEqual(windows.0, "list-windows")
        XCTAssertThrowsError(try ScriptingAlias.resolve(name: "close window", direct: "not-an-id", json: "{}"))
    }
}

@MainActor
final class AdditionalFeatureTests: XCTestCase {
    func testShortcutConflictsAndCaptureBoundsAreReported() {
        var settings = FeatureSettings()
        settings.alternateShortcut = settings.primaryShortcut
        settings.alternateShortcut.enabled = true
        settings.closeKey = settings.quitKey
        settings.dockLiveFrameRate = 300
        settings.dockLiveScale = -2
        settings.normalize()
        XCTAssertEqual(settings.shortcutConflicts.count, 2)
        XCTAssertEqual(settings.dockLiveFrameRate, 30)
        XCTAssertEqual(settings.dockLiveScale, 0.1)
    }
    func testSettingsSearchIncludesAppearanceAndShortcutControls() {
        XCTAssertFalse(SettingsSearch.results(for: "shadow radius").isEmpty)
        XCTAssertFalse(SettingsSearch.results(for: "primary").isEmpty)
        XCTAssertEqual(Set(SettingsSearch.catalog.map(\.id)).count, SettingsSearch.catalog.count)
    }
    func testPartialNestedStyleBackupKeepsUnspecifiedDefaults() throws {
        let value = try FeatureSettings.decode(Data("{\"switcherStyle\":{\"iconOnly\":true,\"maxRows\":999}}".utf8))
        XCTAssertTrue(value.switcherStyle.iconOnly)
        XCTAssertEqual(value.switcherStyle.maxRows, 12)
        XCTAssertEqual(value.switcherStyle.titleFontSize, 12)
    }
    func testInactiveShortcutCancellationDoesNotNotifyOrRecurse() {
        let monitor = GlobalShortcutMonitor(); var calls = 0
        monitor.onCancel = { calls += 1; monitor.endSession() }
        monitor.cancelSwitching(); monitor.endSession()
        XCTAssertEqual(calls, 0)
    }
    func testCommandActionDoesNotEscapeToUnderlyingAppWhileSearching() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true))
        event.flags = .maskCommand
        let model = SwitcherModel(); model.searchText = "report"
        var actions = 0; model.onAction = { _, _ in actions += 1 }
        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: FeatureSettings()))
        XCTAssertEqual(actions, 0)
    }
    func testLargePreviewShortcutRoutesOnlyInsideOverlayWithoutChangingSearch() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true))
        event.flags = .maskCommand
        let model = SwitcherModel()
        model.searchText = "report"
        var opens = 0
        model.onLargePreview = { opens += 1 }
        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: FeatureSettings()))
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(model.searchText, "report")
        var settings = FeatureSettings()
        settings.closeKey = settings.largePreviewKey
        XCTAssertTrue(settings.shortcutConflicts.contains { $0.contains("Large preview") })
        settings.closeKey = 13
        settings.primaryShortcut = Shortcut(keyCode: settings.largePreviewKey, modifier: .command)
        XCTAssertTrue(settings.shortcutConflicts.contains { $0.contains("switcher shortcut") })
        XCTAssertEqual(try FeatureSettings.decode(Data("{\"schemaVersion\":1}".utf8)).largePreviewKey, 35)
    }
    func testOptionSectionKeyTogglesLargePreviewWhileSearchKeepsTypedText() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 10, keyDown: true))
        event.flags = .maskAlternate
        let model = SwitcherModel()
        var toggles = 0
        model.onLargePreview = { toggles += 1 }
        let settings = FeatureSettings()

        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: settings))
        XCTAssertEqual(toggles, 1)
        XCTAssertTrue(model.searchText.isEmpty)

        event.flags = []
        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: settings))
        XCTAssertEqual(toggles, 1)
        event.flags = .maskAlternate

        model.searchText = "report"
        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: settings))
        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(model.searchText, "report§")

        var controlSettings = settings
        controlSettings.largePreviewTrigger = .control
        model.searchText = ""
        XCTAssertTrue(OverlayKeyRouter.handle(event, model: model, settings: controlSettings))
        XCTAssertEqual(toggles, 1)
    }
    func testControlPreviewTriggersOnPressWhileOptionIsHeld() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true))
        let model = SwitcherModel()
        var toggles = 0
        model.onLargePreview = { toggles += 1 }
        var settings = FeatureSettings()
        settings.largePreviewTrigger = .control
        event.flags = [.maskAlternate, .maskControl]
        XCTAssertTrue(OverlayKeyRouter.handleModifier(event, model: model, settings: settings))
        XCTAssertEqual(toggles, 1)
        event.flags = .maskAlternate
        XCTAssertFalse(OverlayKeyRouter.handleModifier(event, model: model, settings: settings))
        XCTAssertEqual(toggles, 1)
        settings.largePreviewTrigger = .section
        event.flags = [.maskAlternate, .maskControl]
        XCTAssertFalse(OverlayKeyRouter.handleModifier(event, model: model, settings: settings))
    }
    func testSessionPreviewHotkeyAvoidsShortcutConflicts() {
        let defaultShortcut = Shortcut(keyCode: 48, modifier: .option)
        XCTAssertTrue(GlobalShortcutMonitor.canRegisterPreviewKey(shortcut: defaultShortcut, backwardKeyCode: 48, previewKeyCode: 10))
        XCTAssertFalse(GlobalShortcutMonitor.canRegisterPreviewKey(shortcut: defaultShortcut, backwardKeyCode: 10, previewKeyCode: 10))
        XCTAssertFalse(GlobalShortcutMonitor.canRegisterPreviewKey(shortcut: defaultShortcut, backwardKeyCode: 48, previewKeyCode: nil))
        XCTAssertFalse(GlobalShortcutMonitor.canRegisterPreviewKey(shortcut: Shortcut(keyCode: 10, modifier: .option), backwardKeyCode: 48, previewKeyCode: 10))
        XCTAssertFalse(GlobalShortcutMonitor.canRegisterPreviewKey(shortcut: Shortcut(keyCode: 48, modifier: .command), backwardKeyCode: 48, previewKeyCode: 10))
        XCTAssertEqual(try? FeatureSettings.decode(Data("{\"schemaVersion\":1}".utf8)).largePreviewTrigger, .section)
    }
    func testLargePreviewFillsAvailableDisplayWithoutClippingLandscapeWindow() {
        let visible = CGRect(x: 100, y: 80, width: 2560, height: 1380)
        let frame = FullSizePreviewLayout.frame(visibleFrame: visible,
                                                sourceSize: CGSize(width: 1920, height: 1080))
        XCTAssertGreaterThan(frame.width, 850)
        XCTAssertGreaterThan(frame.height, 550)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.width / frame.height, 1920.0 / 1080.0, accuracy: 0.001)
    }
    func testLargePreviewKeepsPortraitWindowInsideSmallDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 900, height: 700)
        let frame = FullSizePreviewLayout.frame(visibleFrame: visible,
                                                sourceSize: CGSize(width: 600, height: 1000))
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.width / frame.height, 0.6, accuracy: 0.001)
    }
    func testCustomPrimaryShortcutIsPassedToCarbonInsteadOfSearch() throws {
        var settings = FeatureSettings(); settings.primaryShortcut.keyCode = 1; settings.backwardKey = 2
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 1, keyDown: true))
        event.flags = .maskAlternate
        let model = SwitcherModel()
        XCTAssertFalse(OverlayKeyRouter.handle(event, model: model, settings: settings))
        XCTAssertTrue(model.searchText.isEmpty)
    }
    func testDeniedCalendarPermissionAndExcludedCalendarsYieldNoEvents() {
        let now = Date(); let event = CalendarEntry(id: "1", title: "Meeting", start: now, end: now.addingTimeInterval(300), calendar: "Work", calendarID: "work", allDay: false)
        XCTAssertTrue(CalendarListing.filter([event], authorized: false, now: now, exclusions: []).isEmpty)
        XCTAssertTrue(CalendarListing.filter([event], authorized: true, now: now, exclusions: ["work"]).isEmpty)
        XCTAssertEqual(CalendarListing.filter([event], authorized: true, now: now, exclusions: []).count, 1)
        XCTAssertTrue(CalendarListing.filter([], authorized: true, now: now, exclusions: []).isEmpty)
    }
    func testEmptyMediaMetadataIsSafe() {
        let snapshot = MediaSnapshot.decode([:], pid: 0)
        XCTAssertEqual(snapshot.title, ""); XCTAssertEqual(snapshot.duration, 0)
        XCTAssertNil(snapshot.artwork)
    }
    func testLyricsOptOutNeverInvokesTransport() async throws {
        let service = LyricsService { _ in XCTFail("Network transport invoked without opt-in"); return (Data(), 500) }
        let result = try await service.load(enabled: false, title: "Track", artist: "Artist", album: "Album")
        XCTAssertNil(result)
    }
    func testLyricsProviderUsesPlainFallbackAndHandlesUnavailableTrack() async throws {
        let plain = LyricsService { _ in (Data("{\"syncedLyrics\":null,\"plainLyrics\":\"One\\nTwo\"}".utf8), 200) }
        let result = try await plain.load(enabled: true, title: "Track", artist: "Artist", album: "")
        XCTAssertFalse(result?.synchronized ?? true); XCTAssertEqual(result?.lines.map(\.time), [nil, nil])
        let absent = LyricsService { _ in (Data(), 404) }
        do { _ = try await absent.load(enabled: true, title: "Track", artist: "Artist", album: ""); XCTFail("Expected unavailable error") }
        catch { XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable) }
    }
    func testBackupDoesNotTransferFolderAuthorization() throws {
        let name = "AltTabberTests.\(UUID())"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.features.authorizedFolders = ["/test": Data([1, 2, 3])]
        let data = try settings.exportBackup()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [String: Any])
        XCTAssertTrue((features["authorizedFolders"] as? [String: Any])?.isEmpty == true)
        try settings.importBackup(data)
        XCTAssertEqual(settings.features.authorizedFolders["/test"], Data([1, 2, 3]))
    }
    func testFutureBackupVersionIsRejectedWithoutChangingSettings() throws {
        let name = "AltTabberTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: name) }
        let original = settings.features
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: settings.exportBackup()) as? [String: Any])
        object["version"] = 2
        XCTAssertThrowsError(try settings.importBackup(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(settings.features, original)
    }
    func testCacheLifetimeChangeInvalidatesOldEntries() {
        let cache = ThumbnailCache(); let item = WindowItem(id: 1, processID: 1, appName: "Test", title: "Test", bounds: CGRect(x: 0, y: 0, width: 100, height: 100), appIcon: NSImage(), thumbnail: nil)
        cache.insert(NSImage(), for: item); cache.timeToLive = 30
        XCTAssertNil(cache.image(for: item))
    }
}
