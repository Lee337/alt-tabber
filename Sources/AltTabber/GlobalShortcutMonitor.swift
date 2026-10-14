@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox
@preconcurrency import CoreGraphics

@MainActor
final class GlobalShortcutMonitor {
    var onCycle: ((Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onAlternate: (() -> Void)?
    var onPreviewKey: (() -> Void)?
    var shortcut = Shortcut(keyCode: 48, modifier: .option)
    var backwardKeyCode = 48
    var previewKeyCode: Int? = 10
    var alternate = Shortcut(keyCode: 0, modifier: .control, enabled: false)
    private var alternateHotKey: EventHotKeyRef?
    var initializerFlag: CGEventFlags {
        switch shortcut.modifier { case .option: .maskAlternate; case .control: .maskControl; case .command: .maskCommand }
    }
    private func carbonModifier(_ modifier: ShortcutModifier) -> UInt32 {
        switch modifier { case .option: UInt32(optionKey); case .control: UInt32(controlKey); case .command: UInt32(cmdKey) }
    }

    private enum HotKeyID {
        static let signature: OSType = 0x4154_5442 // "ATTB"
        static let forward: UInt32 = 1
        static let backward: UInt32 = 2
        static let previewKey: UInt32 = 5
    }

    private var forwardHotKey: EventHotKeyRef?
    private var backwardHotKey: EventHotKeyRef?
    private var previewHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var modifierPollingTask: Task<Void, Never>?
    private var isSwitching = false

    var isRunning: Bool {
        forwardHotKey != nil && backwardHotKey != nil && eventHandler != nil
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        stop()

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
        ]
        let callback: EventHandlerUPP = { _, event, userInfo in
            guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(event: event)
            }
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            stop()
            return false
        }

        let target = GetApplicationEventTarget()
        let options = UInt32(kEventHotKeyExclusive)
        let forwardStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifier(shortcut.modifier),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.forward),
            target,
            options,
            &forwardHotKey
        )
        let backwardStatus = RegisterEventHotKey(
            UInt32(backwardKeyCode),
            carbonModifier(shortcut.modifier) | (backwardKeyCode == shortcut.keyCode ? UInt32(shiftKey) : 0),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.backward),
            target,
            options,
            &backwardHotKey
        )

        if alternate.enabled {
            let status = RegisterEventHotKey(UInt32(alternate.keyCode), carbonModifier(alternate.modifier),
                EventHotKeyID(signature: HotKeyID.signature, id: 4), target, options, &alternateHotKey)
            if status != noErr { stop(); return false }
        }
        guard forwardStatus == noErr, backwardStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        endSession()

        if let alternateHotKey { UnregisterEventHotKey(alternateHotKey) }
        alternateHotKey = nil
        if let forwardHotKey { UnregisterEventHotKey(forwardHotKey) }
        if let backwardHotKey { UnregisterEventHotKey(backwardHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }

        forwardHotKey = nil
        backwardHotKey = nil
        eventHandler = nil
    }

    private func handle(event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == HotKeyID.signature else {
            return OSStatus(eventNotHandledErr)
        }

        switch identifier.id {
        case HotKeyID.forward:
            beginOrContinueSwitching(backwards: false)
        case HotKeyID.backward:
            beginOrContinueSwitching(backwards: true)
        case 4:
            onAlternate?()
        case HotKeyID.previewKey:
            if isSwitching { onPreviewKey?() }
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func beginOrContinueSwitching(backwards: Bool) {
        isSwitching = true
        registerPreviewKeyIfNeeded()
        onCycle?(backwards)
        startModifierPollingIfNeeded()
    }

    private func registerPreviewKeyIfNeeded() {
        guard Self.canRegisterPreviewKey(shortcut: shortcut, backwardKeyCode: backwardKeyCode,
                                         previewKeyCode: previewKeyCode),
              let previewKeyCode, previewHotKey == nil else { return }
        let status = RegisterEventHotKey(UInt32(previewKeyCode), UInt32(optionKey),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.previewKey),
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &previewHotKey)
        if status != noErr { previewHotKey = nil }
    }

    static func canRegisterPreviewKey(shortcut: Shortcut, backwardKeyCode: Int, previewKeyCode: Int?) -> Bool {
        guard let previewKeyCode else { return false }
        return shortcut.modifier == .option && shortcut.keyCode != previewKeyCode
            && backwardKeyCode != previewKeyCode
    }

    private func unregisterPreviewKey() {
        if let previewHotKey { UnregisterEventHotKey(previewHotKey) }
        previewHotKey = nil
    }

    private func startModifierPollingIfNeeded() {
        guard modifierPollingTask == nil else { return }
        modifierPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, !Task.isCancelled else { return }
                let flags = CGEventSource.flagsState(.combinedSessionState)
                if !flags.contains(self.initializerFlag) {
                    self.commitSwitching()
                    return
                }
            }
        }
    }

    private func commitSwitching() {
        guard isSwitching else { return }
        isSwitching = false
        modifierPollingTask = nil
        unregisterPreviewKey()
        onCommit?()
    }

    func cancelSwitching() {
        guard isSwitching else { return }
        endSession()
        onCancel?()
    }

    func endSession() {
        isSwitching = false
        modifierPollingTask?.cancel()
        modifierPollingTask = nil
        unregisterPreviewKey()
    }
}
