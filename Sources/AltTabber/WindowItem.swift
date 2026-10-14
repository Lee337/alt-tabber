import AppKit
import CoreGraphics

struct WindowItem: Identifiable {
    let id: CGWindowID
    let processID: pid_t
    let appName: String
    var title: String
    let bounds: CGRect
    let appIcon: NSImage
    var thumbnail: NSImage?
    var bundleIdentifier: String? = nil
    var isOnScreen = true
    var isMinimized = false
    var isHidden = false
    var isFullscreen = false
    var displayID: UInt32? = nil
    var spaceIDs: [UInt64]? = nil
    var createdAt = Date()
    var lastUsedAt = Date.distantPast
    var nativeTabGroup: String? = nil

    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var hasDistinctTitle: Bool {
        !title.isEmpty && title.localizedCaseInsensitiveCompare(appName) != .orderedSame
    }
}
