import AppKit
import ApplicationServices
import Darwin

@MainActor
final class PlatformCapabilities {
    static let shared = PlatformCapabilities()
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Spaces = @convention(c) (UInt32, UInt64, CFArray) -> Unmanaged<CFArray>?
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias Move = @convention(c) (UInt32, CFArray, UInt64) -> Void
    private let handle: UnsafeMutableRawPointer?
    private let connection: Connection?
    private let spaces: Spaces?
    private let displays: Displays?
    private let move: Move?

    init() {
        let loadedHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        handle = loadedHandle
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let loadedHandle, let symbol = dlsym(loadedHandle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        connection = load("CGSMainConnectionID", Connection.self)
        spaces = load("CGSCopySpacesForWindows", Spaces.self)
        displays = load("CGSCopyManagedDisplaySpaces", Displays.self)
        move = load("CGSMoveWindowsToManagedSpace", Move.self)
    }
    var supportsSpaces: Bool { connection != nil && spaces != nil && displays != nil }
    var supportsMovingSpaces: Bool { supportsSpaces && move != nil }
    var explanation: String {
        supportsSpaces ? "Space discovery available. Private APIs are checked at runtime." : "Space discovery unavailable on this macOS version. Space filters cannot be enabled."
    }
    func spaces(for id: CGWindowID) -> [UInt64]? {
        guard let connection, let spaces, let array = spaces(connection(), 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return array.map(\.uint64Value)
    }
    func currentSpaces() -> Set<UInt64>? {
        guard let connection, let displays,
              let list = displays(connection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let ids = list.compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber }.map(\.uint64Value)
        return ids.isEmpty ? nil : Set(ids)
    }
    func bringToCurrentSpace(_ id: CGWindowID) -> Bool {
        guard let connection, let move, let space = currentSpaces()?.sorted().first else { return false }
        move(connection(), [NSNumber(value: id)] as CFArray, space)
        return true
    }
}
