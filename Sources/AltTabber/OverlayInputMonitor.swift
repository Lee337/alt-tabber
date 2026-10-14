import AppKit
import CoreGraphics

@MainActor
final class OverlayInputMonitor {
    var onEvent: ((CGEventType, CGEvent) -> Bool)?
    var customMask: CGEventMask?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .otherMouseDown, .rightMouseDown, .leftMouseDown, .scrollWheel, .mouseMoved]
        let mask = customMask ?? types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let consumed: Bool = MainActor.assumeIsolated {
                let monitor = Unmanaged<OverlayInputMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return false
                }
                return monitor.onEvent?(type, event) == true
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
}

@MainActor
enum OverlayKeyRouter {
    static func handleModifier(_ event: CGEvent, model: SwitcherModel, settings: FeatureSettings) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard settings.largePreviewTrigger.usesControl, (key == 59 || key == 62),
              event.flags.contains(.maskAlternate), event.flags.contains(.maskControl) else { return false }
        model.onLargePreview?()
        return true
    }

    static func handle(_ event: CGEvent, model: SwitcherModel, settings: FeatureSettings) -> Bool {
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if key == 53 { model.cancel(); return true }
        let initializer: CGEventFlags = settings.primaryShortcut.modifier == .option ? .maskAlternate : settings.primaryShortcut.modifier == .control ? .maskControl : .maskCommand
        if event.flags.contains(initializer) && (key == settings.primaryShortcut.keyCode || key == settings.backwardKey) { return false }
        let command = event.flags.contains(.maskCommand)
        if command && key == settings.largePreviewKey { model.onLargePreview?(); return true }
        if key == 10 && model.surface == .switcher && event.flags.contains(.maskAlternate)
            && settings.largePreviewTrigger.usesSection
            && !command && !event.flags.contains(.maskControl)
            && model.searchText.isEmpty && settings.selectionKey != 10 {
            model.onLargePreview?(); return true
        }
        if key == settings.selectionKey { model.commit(); return true }
        if command && model.searchText.isEmpty {
            if key == settings.closeKey { model.perform(settings.closeKeyAction); return true }
            if key == settings.minimizeKey { model.perform(settings.minimizeKeyAction); return true }
            if key == settings.quitKey { model.perform(event.flags.contains(.maskAlternate) && settings.quitKeyAction == .quit ? .forceQuit : settings.quitKeyAction); return true }
        }
        if settings.passArrowsThrough && (123...126).contains(key) { return false }
        if key == 123 { model.move(-1); return true }
        if key == 124 { model.move(1); return true }
        if key == 125 { model.move(model.gridColumnCount); return true }
        if key == 126 { model.move(-model.gridColumnCount); return true }
        if key == 48 {
            // Primary shortcut remains registered through Carbon.
            let initializer: CGEventFlags = settings.primaryShortcut.modifier == .option ? .maskAlternate : settings.primaryShortcut.modifier == .control ? .maskControl : .maskCommand
            if event.flags.contains(initializer), settings.primaryShortcut.keyCode == key { return false }
            model.cycle(backwards: event.flags.contains(.maskShift)); return true
        }
        if settings.vimNavigation && model.searchText.isEmpty && !command {
            switch key {
            case 4: model.move(-1); return true
            case 38: model.move(model.gridColumnCount); return true
            case 40: model.move(-model.gridColumnCount); return true
            case 37: model.move(1); return true
            default: break
            }
        }
        if settings.searchEnabled && !command && !event.flags.contains(.maskControl) {
            if key == 51 { if !model.searchText.isEmpty { model.searchText.removeLast() }; return true }
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 32)
            event.keyboardGetUnicodeString(maxStringLength: 32, actualStringLength: &length, unicodeString: &buffer)
            let text = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? String(utf16CodeUnits: buffer, count: length)
            if text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }), !text.isEmpty {
                if key != settings.searchKey || !model.searchText.isEmpty { model.searchText += text }
                return true
            }
        }
        return true
    }
}
