import AppKit
import Combine
@preconcurrency import EventKit
import Foundation

struct FolderEntry: Identifiable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let modified: Date
    let created: Date
    let size: Int
    var id: URL { url }
}

enum FolderListing {
    static func read(_ url: URL, hidden: Bool, sort: FolderSort, descending: Bool) throws -> [FolderEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys),
            options: hidden ? [] : [.skipsHiddenFiles])
        let entries = contents.map { item in
            let values = try? item.resourceValues(forKeys: keys)
            return FolderEntry(url: item, name: item.lastPathComponent, isDirectory: values?.isDirectory ?? false,
                modified: values?.contentModificationDate ?? .distantPast, created: values?.creationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
        return sorted(entries, by: sort, descending: descending)
    }
    static func sorted(_ entries: [FolderEntry], by sort: FolderSort, descending: Bool) -> [FolderEntry] {
        entries.sorted { a, b in
            let comparison: ComparisonResult
            switch sort {
            case .name: comparison = a.name.localizedStandardCompare(b.name)
            case .modified: comparison = a.modified.compare(b.modified)
            case .created: comparison = a.created.compare(b.created)
            case .size: comparison = a.size == b.size ? .orderedSame : a.size < b.size ? .orderedAscending : .orderedDescending
            case .kind: comparison = a.url.pathExtension.localizedStandardCompare(b.url.pathExtension)
            }
            if comparison == .orderedSame { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}

@MainActor
final class FolderWidgetModel: ObservableObject {
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var error: String?
    @Published var sort: FolderSort
    let url: URL
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var authorizedURL: URL?
    init(url: URL, settings: AppSettings) {
        self.url = url; self.settings = settings
        sort = settings.features.folderSorts[url.path] ?? settings.features.folderSort
    }
    func load() {
        task?.cancel()
        let url = authorizedURL ?? url
        let hidden = settings.features.folderShowHidden
        let descending = settings.features.folderDescending
        let sort = sort
        if settings.features.folderRememberSort { settings.features.folderSorts[self.url.path] = sort }
        task = Task { [weak self] in
            let result = await Task.detached { () -> Result<[FolderEntry], Error> in
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                return Result { try FolderListing.read(url, hidden: hidden, sort: sort, descending: descending) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let entries): self.entries = entries; error = nil
            case .failure(let failure): entries = []; error = failure.localizedDescription
            }
        }
    }
    func authorize() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = url; panel.message = "Choose this folder to allow AltTabber to preview its contents."
        if panel.runModal() == .OK, let selected = panel.url,
           let bookmark = try? selected.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.features.authorizedFolders[url.path] = bookmark; authorizedURL = selected; load()
        }
    }
    func restoreAuthorization() {
        guard let data = settings.features.authorizedFolders[url.path] else { return }
        var stale = false
        authorizedURL = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { error = "Folder authorization expired. Choose the folder again." }
    }
    func stop() { task?.cancel() }
    deinit { task?.cancel() }
}

struct CalendarEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendar: String
    let calendarID: String
    let allDay: Bool
}
@MainActor
final class CalendarWidgetModel: ObservableObject {
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var permissionGranted = false
    @Published private(set) var error: String?
    private let store = EKEventStore()
    private let settings: AppSettings
    init(settings: AppSettings) { self.settings = settings }
    func requestAccess() async {
        do { permissionGranted = try await store.requestFullAccessToEvents(); refresh() }
        catch { self.error = error.localizedDescription }
    }
    func refresh() {
        permissionGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard permissionGranted else { entries = []; return }
        let start = Date(); let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: start)) ?? start
        let exclusions = WindowQuery.tokens(settings.features.calendarExclusions)
        let calendars = store.calendars(for: .event).filter { !exclusions.contains($0.calendarIdentifier) && !exclusions.contains($0.title) }
        guard !calendars.isEmpty else { entries = []; return }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
        let loaded = events.map {
            CalendarEntry(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate,
                end: $0.endDate, calendar: $0.calendar.title, calendarID: $0.calendar.calendarIdentifier, allDay: $0.isAllDay)
        }
        entries = CalendarListing.filter(loaded, authorized: permissionGranted, now: start, exclusions: exclusions)
    }
}

struct LyricsLine: Identifiable, Equatable, Sendable {
    let time: Double?
    let text: String
    var id: String { "\(time ?? -1):\(text)" }
}
enum LyricsParser {
    static func parse(_ text: String, synchronized: Bool) -> [LyricsLine] {
        text.components(separatedBy: .newlines).compactMap { raw in
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            if !synchronized { return LyricsLine(time: nil, text: raw) }
            guard raw.first == "[", let bracket = raw.firstIndex(of: "]") else { return nil }
            let time = raw[raw.index(after: raw.startIndex)..<bracket].split(separator: ":")
            guard time.count == 2, let minutes = Double(time[0]), let seconds = Double(time[1]) else { return nil }
            return LyricsLine(time: minutes * 60 + seconds, text: String(raw[raw.index(after: bracket)...]))
        }.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }
}

@MainActor
final class MediaWidgetModel: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration = 0.0
    @Published var position = 0.0
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lyrics: [LyricsLine] = []
    @Published private(set) var synchronizedLyrics = false
    let bundleIdentifier: String
    private let settings: AppSettings
    private var task: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var trackIdentity = ""
    private var volumeLevel = 50.0
    deinit { task?.cancel(); lyricsTask?.cancel() }
    init(bundleIdentifier: String, settings: AppSettings) { self.bundleIdentifier = bundleIdentifier; self.settings = settings }
    var supportsAutomation: Bool { ["com.apple.Music", "com.spotify.client"].contains(bundleIdentifier) }
    func start() {
        stop()
        guard supportsAutomation || UniversalMediaAdapter.shared.available else { error = UniversalMediaAdapter.shared.explanation; return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func stop() { task?.cancel(); task = nil; lyricsTask?.cancel(); lyricsTask = nil }
    private func script(_ command: String) -> NSAppleEventDescriptor? {
        guard supportsAutomation else { return nil }
        let source = "tell application id \"\(bundleIdentifier)\"\n\(command)\nend tell"
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo { error = errorInfo[NSAppleScript.errorMessage] as? String ?? "Automation access is required." }
        else { error = nil }
        return result
    }
    func refresh() {
        UniversalMediaAdapter.shared.refresh()
        if let snapshot = UniversalMediaAdapter.shared.snapshot,
           NSRunningApplication(processIdentifier: snapshot.processID)?.bundleIdentifier == bundleIdentifier,
           !snapshot.title.isEmpty {
            title = snapshot.title; artist = snapshot.artist; album = snapshot.album
            duration = snapshot.duration; position = snapshot.elapsed; playing = snapshot.rate > 0
            artwork = snapshot.artwork.flatMap(NSImage.init(data:))
            updateTrackIdentity(); return
        }
        guard supportsAutomation else { error = UniversalMediaAdapter.shared.explanation; return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first != nil else {
            title = "No media app running"; playing = false; return
        }
        let command: String
        if bundleIdentifier == "com.spotify.client" {
            command = "if not exists current track then return {}\nreturn {name of current track, artist of current track, album of current track, duration of current track / 1000, player position, player state as string}"
        } else {
            command = "if not exists current track then return {}\nreturn {name of current track, artist of current track, album of current track, duration of current track, player position, player state as string}"
        }
        guard let result = script(command), result.numberOfItems >= 6 else { title = "Nothing playing"; return }
        title = result.atIndex(1)?.stringValue ?? ""; artist = result.atIndex(2)?.stringValue ?? ""
        album = result.atIndex(3)?.stringValue ?? ""
        duration = Double(result.atIndex(4)?.stringValue ?? "") ?? Double(result.atIndex(4)?.int32Value ?? 0)
        position = Double(result.atIndex(5)?.stringValue ?? "") ?? Double(result.atIndex(5)?.int32Value ?? 0)
        playing = result.atIndex(6)?.stringValue == "playing"
        updateTrackIdentity()
    }
    private func updateTrackIdentity() {
        let identity = "\(title)|\(artist)|\(album)"
        if identity != trackIdentity { trackIdentity = identity; lyrics = []; lyricsTask?.cancel() }
    }
    private var usesUniversal: Bool {
        guard let snapshot = UniversalMediaAdapter.shared.snapshot else { return false }
        return NSRunningApplication(processIdentifier: snapshot.processID)?.bundleIdentifier == bundleIdentifier && !snapshot.title.isEmpty
    }
    func playPause() { if usesUniversal { _ = UniversalMediaAdapter.shared.toggle() } else { _ = script("playpause") }; refresh() }
    func next() { if usesUniversal { _ = UniversalMediaAdapter.shared.next() } else { _ = script("next track") }; refresh() }
    func previous() { if usesUniversal { _ = UniversalMediaAdapter.shared.previous() } else { _ = script("previous track") }; refresh() }
    func seek(_ seconds: Double) {
        if usesUniversal { _ = UniversalMediaAdapter.shared.seek(min(duration, max(0, seconds))) }
        else { _ = script("set player position to \(max(0, min(duration, seconds)))") }
        refresh()
    }
    func cancelLyrics() { lyricsTask?.cancel(); lyricsTask = nil; lyrics = [] }
    func volume(_ value: Double) {
        volumeLevel = max(0, min(100, value))
        if supportsAutomation { _ = script("set sound volume to \(Int(volumeLevel))") }
        else if !AudioDevices.setVolume(volumeLevel / 100) { error = "This output device does not support software volume control." }
    }
    func scroll(_ delta: Double) {
        if settings.features.mediaScrollSeek { seek(position + delta * 2) }
        else { volume(volumeLevel + delta * 2) }
    }
    func fetchLyrics() {
        guard settings.features.lyricsEnabled, !title.isEmpty, !artist.isEmpty else { return }
        lyricsTask?.cancel()
        let identity = trackIdentity
        let title = title; let artist = artist; let album = album
        lyricsTask = Task { [weak self] in
            do {
                let response = try await LyricsService().load(enabled: true, title: title, artist: artist, album: album)
                guard let self, !Task.isCancelled, settings.features.lyricsEnabled, identity == trackIdentity else { return }
                synchronizedLyrics = response?.synchronized ?? false
                lyrics = response?.lines ?? []
                if lyrics.isEmpty { error = "Lyrics unavailable for this track." }
            } catch { if !Task.isCancelled { self?.error = "Lyrics unavailable: \(error.localizedDescription)" } }
        }
    }
}
