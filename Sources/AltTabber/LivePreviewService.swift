import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage

private final class StreamFrames: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let id: CGWindowID
    let deliver: @Sendable (CGWindowID, CGImage) -> Void
    let failure: @Sendable (CGWindowID, String) -> Void
    private let context = CIContext(options: [.cacheIntermediates: false])
    init(id: CGWindowID, deliver: @escaping @Sendable (CGWindowID, CGImage) -> Void, failure: @escaping @Sendable (CGWindowID, String) -> Void) {
        self.id = id; self.deliver = deliver; self.failure = failure
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failure(id, error.localizedDescription) }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, let pixel = buffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixel)
        if let cg = context.createCGImage(image, from: image.extent) { deliver(id, cg) }
    }
}

@MainActor
final class LivePreviewService {
    private var streams: [CGWindowID: (SCStream, StreamFrames)] = [:]
    private var streamTokens: [CGWindowID: UUID] = [:]
    private var processes: [CGWindowID: pid_t] = [:]
    private var configurationKey = ""
    private var desiredIDs = Set<CGWindowID>()
    private var generation = UUID()
    private var keepAliveTask: Task<Void, Never>?
    var onImage: ((CGWindowID, NSImage) -> Void)?
    var onFailure: ((String) -> Void)?
    var activeCount: Int { streams.count }

    func update(windows: [WindowItem], settings: FeatureSettings) async {
        keepAliveTask?.cancel(); keepAliveTask = nil
        let wanted = Set(windows.filter { !$0.isMinimized && !$0.isHidden }.map(\.id))
        let key = "\(settings.liveScale):\(settings.liveFrameRate)"
        let requestedProcesses = Dictionary(windows.map { ($0.id, $0.processID) }, uniquingKeysWith: { a, _ in a })
        if wanted == desiredIDs && wanted == Set(streams.keys) && key == configurationKey && processes == requestedProcesses { return }
        let changedConfiguration = key != configurationKey
        configurationKey = key
        desiredIDs = wanted
        let session = UUID(); generation = session
        for id in Array(streams.keys) where changedConfiguration || !wanted.contains(id) || processes[id] != requestedProcesses[id] {
            streamTokens[id] = nil; processes[id] = nil
            if let pair = streams.removeValue(forKey: id) { try? await pair.0.stopCapture() }
        }
        guard !wanted.isEmpty, PermissionManager.hasScreenRecordingAccess else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard session == generation, !Task.isCancelled else { return }
            for window in content.windows where wanted.contains(window.windowID) && streams[window.windowID] == nil {
                guard session == generation, !Task.isCancelled else { return }
                let id = window.windowID
                let config = SCStreamConfiguration()
                config.width = max(1, min(900, Int(window.frame.width * settings.liveScale)))
                config.height = max(1, min(600, Int(window.frame.height * settings.liveScale)))
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.liveFrameRate))
                config.showsCursor = false; config.queueDepth = 3
                let streamToken = UUID()
                let output = StreamFrames(id: id, deliver: { [weak self] id, image in
                    Task { @MainActor [weak self] in
                        guard let self, self.streamTokens[id] == streamToken else { return }
                        self.onImage?(id, NSImage(cgImage: image, size: .zero))
                    }
                }, failure: { [weak self] id, message in
                    Task { @MainActor [weak self] in
                        guard let self, self.streamTokens[id] == streamToken else { return }
                        self.streams[id] = nil; self.streamTokens[id] = nil; self.processes[id] = nil
                        self.onFailure?(message)
                    }
                })
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "AltTabber.capture.\(id)"))
                try await stream.startCapture()
                guard session == generation, !Task.isCancelled else { try? await stream.stopCapture(); return }
                streams[id] = (stream, output)
                streamTokens[id] = streamToken; processes[id] = requestedProcesses[id]
            }
        } catch { onFailure?(error.localizedDescription) }
    }
    func stop(after delay: Double = 0) {
        generation = UUID()
        desiredIDs = []
        keepAliveTask?.cancel()
        keepAliveTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            let previous = self.streams; self.streams.removeAll(); self.streamTokens.removeAll(); self.processes.removeAll()
            for pair in previous.values { try? await pair.0.stopCapture() }
        }
    }
}
