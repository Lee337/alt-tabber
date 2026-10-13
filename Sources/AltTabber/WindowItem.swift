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

    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var hasDistinctTitle: Bool {
        !title.isEmpty && title.localizedCaseInsensitiveCompare(appName) != .orderedSame
    }
}
