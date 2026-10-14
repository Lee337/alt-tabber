import AppKit
import Foundation

enum CustomDockEdge: String, Codable, CaseIterable {
    case bottom, left, right
}

enum CustomDockPinKind: String, Codable {
    case application, folder, file, link, separator
}

struct CustomDockPin: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var kind: CustomDockPinKind
    var title: String
    var location: String

    static func application(_ url: URL) -> Self {
        Self(kind: .application, title: url.deletingPathExtension().lastPathComponent,
             location: url.standardizedFileURL.path)
    }
    static func file(_ url: URL, isDirectory: Bool) -> Self {
        Self(kind: isDirectory ? .folder : .file, title: url.lastPathComponent,
             location: url.standardizedFileURL.path)
    }
    static func link(_ url: URL) -> Self {
        Self(kind: .link, title: url.host ?? url.absoluteString, location: url.absoluteString)
    }
}

struct CustomDockProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var pins: [CustomDockPin]
    var showRunningApps: Bool
    var linkedAppBundleIDs: [String] = []

    init(id: String, name: String, pins: [CustomDockPin], showRunningApps: Bool, linkedAppBundleIDs: [String] = []) {
        self.id = id; self.name = name; self.pins = pins
        self.showRunningApps = showRunningApps; self.linkedAppBundleIDs = linkedAppBundleIDs
    }

    private enum CodingKeys: String, CodingKey { case id, name, pins, showRunningApps, linkedAppBundleIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        pins = try values.decode([CustomDockPin].self, forKey: .pins)
        showRunningApps = try values.decode(Bool.self, forKey: .showRunningApps)
        linkedAppBundleIDs = try values.decodeIfPresent([String].self, forKey: .linkedAppBundleIDs) ?? []
    }

    static let initial = Self(id: "default", name: "Default", pins: [], showRunningApps: true)

    mutating func movePin(_ id: String, before destinationID: String) {
        guard id != destinationID, let source = pins.firstIndex(where: { $0.id == id }),
              let destination = pins.firstIndex(where: { $0.id == destinationID }) else { return }
        let pin = pins.remove(at: source)
        let updatedDestination = pins.firstIndex(where: { $0.id == destinationID }) ?? destination
        pins.insert(pin, at: updatedDestination)
    }

    @discardableResult mutating func importApplications(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.pathExtension.lowercased() == "app" {
            let candidate = CustomDockPin.application(url)
            guard !pins.contains(where: { $0.kind == .application && $0.location == candidate.location }) else { continue }
            pins.append(candidate)
            added += 1
        }
        return added
    }
}

struct CustomDockRunningApp: Equatable {
    let processID: pid_t
    let bundleIdentifier: String?
    let bundlePath: String?
    let name: String
}

struct CustomDockResolvedItem: Identifiable, Equatable {
    let id: String
    let title: String
    let location: String?
    let processID: pid_t?
    let isPinned: Bool
    let kind: CustomDockPinKind
}

enum CustomDockContent {
    static func resolve(profile: CustomDockProfile, running: [CustomDockRunningApp]) -> [CustomDockResolvedItem] {
        var result = profile.pins.map { pin in
            CustomDockResolvedItem(id: pin.id, title: pin.title, location: pin.location,
                processID: running.first(where: { matches(pin, $0) })?.processID,
                isPinned: true, kind: pin.kind)
        }
        guard profile.showRunningApps else { return result }
        let pinned = Set(profile.pins.filter { $0.kind == .application }.map { URL(fileURLWithPath: $0.location).standardizedFileURL.path })
        let extras = running.filter { app in
            guard let path = app.bundlePath else { return true }
            return !pinned.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result += extras.map { app in
            CustomDockResolvedItem(id: "running:\(app.processID)", title: app.name, location: app.bundlePath,
                processID: app.processID, isPinned: false, kind: .application)
        }
        return result
    }

    private static func matches(_ pin: CustomDockPin, _ app: CustomDockRunningApp) -> Bool {
        guard pin.kind == .application, let path = app.bundlePath else { return false }
        return URL(fileURLWithPath: pin.location).standardizedFileURL == URL(fileURLWithPath: path).standardizedFileURL
    }
}

extension FeatureSettings {
    @discardableResult mutating func stageDockFile(_ url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return false }
        let path = url.standardizedFileURL.path
        guard !customDockStagedFiles.contains(path), customDockStagedFiles.count < 100 else { return false }
        customDockStagedFiles.append(path)
        return true
    }
    mutating func removeStagedDockFile(_ path: String) {
        customDockStagedFiles.removeAll { $0 == path }
    }
    var selectedDockProfile: CustomDockProfile {
        dockProfiles.first { $0.id == activeDockProfileID } ?? dockProfiles[0]
    }
    mutating func updateDockProfile(_ profile: CustomDockProfile) {
        guard let index = dockProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        dockProfiles[index] = profile
    }
    mutating func removeDockProfile(_ id: String) {
        guard dockProfiles.count > 1 else { return }
        dockProfiles.removeAll { $0.id == id }
        if activeDockProfileID == id { activeDockProfileID = dockProfiles[0].id }
        displayDockProfiles = displayDockProfiles.filter { $0.value != id }
    }
    func dockProfile(for displayID: String, frontmostBundleID: String? = nil) -> CustomDockProfile {
        let automaticID = customDockAppSenseEnabled ? dockProfiles.first(where: { profile in
            guard let frontmostBundleID else { return false }
            return profile.linkedAppBundleIDs.contains { $0.caseInsensitiveCompare(frontmostBundleID) == .orderedSame }
        })?.id : nil
        let id = displayDockProfiles[displayID] ?? automaticID ?? activeDockProfileID
        return dockProfiles.first { $0.id == id } ?? selectedDockProfile
    }
}
