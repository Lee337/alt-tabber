import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

@MainActor
enum PermissionManager {
    private enum PromptKey {
        static let accessibility = "didAutomaticallyRequestAccessibility"
        static let screenRecording = "didAutomaticallyRequestScreenRecording"
    }

    private static let defaults = UserDefaults.standard

    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        defaults.set(true, forKey: PromptKey.accessibility)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestAccessibilityAccessOnce() -> Bool {
        guard !hasAccessibilityAccess else { return true }
        guard !defaults.bool(forKey: PromptKey.accessibility) else { return false }
        return requestAccessibilityAccess()
    }

    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        defaults.set(true, forKey: PromptKey.screenRecording)
        return CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccessOnce() -> Bool {
        guard !hasScreenRecordingAccess else { return true }
        guard !defaults.bool(forKey: PromptKey.screenRecording) else { return false }
        return requestScreenRecordingAccess()
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
