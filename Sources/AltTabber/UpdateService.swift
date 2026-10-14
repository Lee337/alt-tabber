import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateService: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private var feed: URL?
    private var channel: UpdateChannel?
    var configured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "").isEmpty
    }
    func configure(_ settings: FeatureSettings) {
        guard configured else { controller = nil; return }
        if controller == nil || channel != settings.updateChannel {
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            channel = settings.updateChannel
            let key = settings.updateChannel == .stable ? "SUFeedURL" : "AltTabberNightlyFeedURL"
            if let feed = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               let url = URL(string: feed), url.scheme == "https" {
                self.feed = url
                controller?.updater.automaticallyChecksForUpdates = settings.updatesEnabled
                try? controller?.updater.start()
            }
        }
        controller?.updater.automaticallyChecksForUpdates = settings.updatesEnabled
        controller?.updater.automaticallyDownloadsUpdates = false
    }
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { feed?.absoluteString }
    }
    func check() {
        if let controller { controller.checkForUpdates(nil) }
        else { NSWorkspace.shared.open(URL(string: "https://github.com/Lee337/alt-tabber/releases")!) }
    }
}
