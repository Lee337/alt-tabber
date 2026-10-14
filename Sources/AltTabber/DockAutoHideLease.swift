import AppKit
import Darwin

@MainActor
final class DockAutoHideLease {
    private typealias Read = @convention(c) () -> Bool
    private typealias Write = @convention(c) (Bool) -> Void
    private let handle: UnsafeMutableRawPointer?
    private let read: Read?
    private let write: Write?
    private var original: Bool?
    init() {
        let loaded = dlopen("/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock", RTLD_LAZY)
        handle = loaded
        read = loaded.flatMap { dlsym($0, "CoreDockGetAutoHideEnabled") }.map { unsafeBitCast($0, to: Read.self) }
        write = loaded.flatMap { dlsym($0, "CoreDockSetAutoHideEnabled") }.map { unsafeBitCast($0, to: Write.self) }
    }
    var available: Bool { read != nil && write != nil }
    func acquire() {
        guard original == nil, let read, let write else { return }
        original = read(); write(false)
    }
    func release() {
        if let original { write?(original) }
        original = nil
    }
}

@MainActor
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    var enabled = false
    private var records: [String] = []
    func record(_ message: String) {
        guard enabled else { return }
        records.append("\(Date().ISO8601Format()) \(message)")
        if records.count > 200 { records.removeFirst(records.count - 200) }
    }
    var text: String { records.joined(separator: "\n") }
}
