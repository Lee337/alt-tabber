import AppKit
import SwiftUI

struct FolderWidgetView: View {
    @ObservedObject var model: FolderWidgetModel
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(model.url.lastPathComponent).font(.headline)
                Spacer()
                Picker("Sort", selection: $model.sort) {
                    ForEach(FolderSort.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(width: 150)
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("Choose Folder…") { model.authorize() }
            }
            if model.entries.isEmpty && model.error == nil { ContentUnavailableView("Folder Is Empty", systemImage: "folder") }
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(model.entries) { entry in
                        Button {
                            NSWorkspace.shared.open(entry.url)
                        } label: {
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 24, height: 24)
                                Text(entry.name).lineLimit(1)
                                Spacer()
                            }.padding(4)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button("Open in Finder") { NSWorkspace.shared.open(model.url) }
        }.onAppear { model.restoreAuthorization(); model.load() }.onDisappear { model.stop() }
            .onChange(of: model.sort) { _, _ in model.load() }
    }
}
struct CalendarWidgetView: View {
    @ObservedObject var model: CalendarWidgetModel
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("Today’s Events").font(.headline); Spacer(); Button("Refresh") { model.refresh() } }
            if !model.permissionGranted {
                Text("Calendar access is needed to show today’s events.")
                Button("Allow Calendar Access…") { Task { await model.requestAccess() } }
            } else if model.entries.isEmpty { ContentUnavailableView("No Upcoming Events", systemImage: "calendar") }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.entries) { event in
                        VStack(alignment: .leading) {
                            Text(event.title).font(.headline)
                            Text(event.allDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                            Text(event.calendar).font(.caption).foregroundStyle(.secondary)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Button("Open Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        }.task {
            model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }; model.refresh()
            }
        }
    }
}
struct MediaWidgetView: View {
    @ObservedObject var model: MediaWidgetModel
    @ObservedObject var settings: AppSettings
    @State private var volume = 50.0
    @State private var output: UInt32 = AudioDevices.current()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let artwork = model.artwork { Image(nsImage: artwork).resizable().scaledToFit().frame(height: 100) }
            Text(model.title.isEmpty ? "Now Playing" : model.title).font(.headline)
            Text(model.artist).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { model.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { model.playPause() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                Button { model.next() } label: { Image(systemName: "forward.end.fill") }
                Spacer()
                Text("\(Int(model.position)) / \(Int(model.duration)) s").font(.caption)
            }
            Slider(value: $model.position, in: 0...max(1, model.duration), onEditingChanged: { editing in if !editing { model.seek(model.position) } })
                .accessibilityLabel("Playback position")
            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: $volume, in: 0...100, onEditingChanged: { editing in if !editing { model.volume(volume) } }).accessibilityLabel("Volume")
            }
            Picker("Audio Output", selection: $output) { ForEach(AudioDevices.outputs()) { Text($0.name).tag($0.id) } }
                .onChange(of: output) { _, id in if !AudioDevices.select(id) { output = AudioDevices.current() } }
            if settings.features.lyricsEnabled {
                Button("Show Lyrics") { model.fetchLyrics() }
                if !model.lyrics.isEmpty {
                    Text(model.synchronizedLyrics ? "Synchronized lyrics" : "Plain lyrics — no timing available").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(model.lyrics.enumerated()), id: \.offset) { _, line in
                                Text(line.text).foregroundStyle(line.time.map { $0 <= model.position } == true ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
        }.background(MediaScrollMonitor { model.scroll($0) })
        .onAppear { model.start() }.onDisappear { model.stop() }
        .onChange(of: settings.features.lyricsEnabled) { _, enabled in if !enabled { model.cancelLyrics() } }
    }
}

@MainActor
final class WidgetPanelController: NSObject, NSWindowDelegate {
    private var hoverPanel: NSPanel?
    private var pinnedPanels: [NSPanel] = []
    var containsPointer: Bool { hoverPanel?.frame.contains(NSEvent.mouseLocation) == true }
    func show<Content: View>(_ content: Content, title: String, near frame: CGRect, settings: AppSettings) {
        hide()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 430, height: 450), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.delegate = self
        panel.title = title; panel.level = .statusBar; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        let view = VStack {
            if settings.features.pinWidgets {
                HStack { Spacer(); Button("Pin to Screen") { [weak self, weak panel] in
                    guard let self, let panel else { return }
                    hoverPanel = nil; pinnedPanels.append(panel)
                } }
            }
            content
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
        panel.contentViewController = NSHostingController(rootView: view)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let anchor = WindowGeometry.accessibilityFrame(frame, desktopTop: top)
        let visible = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        panel.setFrameOrigin(CGPoint(x: max(visible.minX, min(anchor.midX - 215, visible.maxX - 430)),
            y: max(visible.minY, min(anchor.maxY + 8, visible.maxY - 450))))
        hoverPanel = panel; panel.orderFrontRegardless()
    }
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        if hoverPanel === panel { hoverPanel = nil }
        pinnedPanels.removeAll { $0 === panel }
        panel.contentViewController = nil
    }
    func hide() { hoverPanel?.orderOut(nil); hoverPanel?.contentViewController = nil; hoverPanel = nil }
    func closeAll() {
        hide()
        for panel in pinnedPanels { panel.orderOut(nil); panel.contentViewController = nil }
        pinnedPanels.removeAll()
    }
}

private struct MediaScrollMonitor: NSViewRepresentable {
    let action: (Double) -> Void
    func makeNSView(context: Context) -> MediaScrollView { MediaScrollView() }
    func updateNSView(_ view: MediaScrollView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: MediaScrollView, coordinator: ()) { view.stop() }
}
private final class MediaScrollView: NSView {
    var action: ((Double) -> Void)?
    private var token: Any?
    private var lastAction = Date.distantPast
    override func viewDidMoveToWindow() {
        stop()
        guard window != nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)),
                  Date().timeIntervalSince(lastAction) > 0.2 else { return event }
            lastAction = Date(); action?(event.scrollingDeltaY); return nil
        }
    }
    func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
}
