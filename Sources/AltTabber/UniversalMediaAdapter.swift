import AppKit
import Darwin

struct MediaSnapshot: Sendable, Equatable {
    let processID: Int32
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let elapsed: Double
    let rate: Double
    let artwork: Data?
    static func decode(_ metadata: [String: Any], pid: Int32) -> Self {
        Self(processID: pid, title: metadata["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "",
             artist: metadata["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
             album: metadata["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
             duration: metadata["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
             elapsed: metadata["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0,
             rate: metadata["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0,
             artwork: metadata["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
    }
}

@MainActor
final class UniversalMediaAdapter {
    static let shared = UniversalMediaAdapter()
    private typealias ReadInfo = @convention(c) (DispatchQueue, @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias ReadPID = @convention(c) (DispatchQueue, @convention(block) (Int32) -> Void) -> Void
    private typealias Command = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias Seek = @convention(c) (Double) -> Void
    private let handle: UnsafeMutableRawPointer?
    private let info: ReadInfo?
    private let pid: ReadPID?
    private let command: Command?
    private let seekFunction: Seek?
    private(set) var snapshot: MediaSnapshot?
    private var generation = UUID()
    private var lastRequest = Date.distantPast
    var available: Bool { info != nil && pid != nil }
    var explanation: String {
        available ? "Universal media APIs are loaded. macOS may restrict access; Music and Spotify use Automation as a fallback." : "Universal media APIs are unavailable. Music and Spotify use Automation controls."
    }
    init() {
        let loaded = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        handle = loaded
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let loaded, let address = dlsym(loaded, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        info = symbol("MRMediaRemoteGetNowPlayingInfo", as: ReadInfo.self)
        pid = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: ReadPID.self)
        command = symbol("MRMediaRemoteSendCommand", as: Command.self)
        seekFunction = symbol("MRMediaRemoteSetElapsedTime", as: Seek.self)
    }
    func refresh() {
        guard Date().timeIntervalSince(lastRequest) >= 1, let pid, let info else { return }
        lastRequest = Date(); let token = generation
        pid(.main) { [weak self] process in
            info(.main) { dictionary in
                let snapshot = (dictionary as? [String: Any]).map { MediaSnapshot.decode($0, pid: process) }
                Task { @MainActor [weak self] in
                    guard let self, token == generation else { return }
                    self.snapshot = snapshot
                }
            }
        }
    }
    func stop() { generation = UUID(); snapshot = nil }
    func toggle() -> Bool { command?(2, nil) ?? false }
    func next() -> Bool { command?(4, nil) ?? false }
    func previous() -> Bool { command?(5, nil) ?? false }
    func seek(_ seconds: Double) -> Bool {
        guard let seekFunction else { return false }
        seekFunction(max(0, seconds)); return true
    }
}
