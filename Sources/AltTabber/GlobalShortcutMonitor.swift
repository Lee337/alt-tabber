@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox
@preconcurrency import CoreGraphics

@MainActor
final class GlobalShortcutMonitor {
    var onCycle: ((Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private enum HotKeyID {
        static let signature: OSType = 0x4154_5442 // "ATTB"
        static let forward: UInt32 = 1
        static let backward: UInt32 = 2
        static let cancel: UInt32 = 3
    }

    private var forwardHotKey: EventHotKeyRef?
    private var backwardHotKey: EventHotKeyRef?
    private var cancelHotKey: EventHotKeyRef?
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
            UInt32(kVK_Tab),
            UInt32(optionKey),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.forward),
            target,
            options,
            &forwardHotKey
        )
        let backwardStatus = RegisterEventHotKey(
            UInt32(kVK_Tab),
            UInt32(optionKey | shiftKey),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.backward),
            target,
            options,
            &backwardHotKey
        )
        let cancelStatus = RegisterEventHotKey(
            UInt32(kVK_Escape),
            UInt32(optionKey),
            EventHotKeyID(signature: HotKeyID.signature, id: HotKeyID.cancel),
            target,
            options,
            &cancelHotKey
        )

        guard forwardStatus == noErr, backwardStatus == noErr, cancelStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        modifierPollingTask?.cancel()
        modifierPollingTask = nil
        isSwitching = false

        if let forwardHotKey { UnregisterEventHotKey(forwardHotKey) }
        if let backwardHotKey { UnregisterEventHotKey(backwardHotKey) }
        if let cancelHotKey { UnregisterEventHotKey(cancelHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }

        forwardHotKey = nil
        backwardHotKey = nil
        cancelHotKey = nil
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
        case HotKeyID.cancel where isSwitching:
            cancelSwitching()
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func beginOrContinueSwitching(backwards: Bool) {
        isSwitching = true
        onCycle?(backwards)
        startModifierPollingIfNeeded()
    }

    private func startModifierPollingIfNeeded() {
        guard modifierPollingTask == nil else { return }
        modifierPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard let self, !Task.isCancelled else { return }
                let flags = CGEventSource.flagsState(.combinedSessionState)
                if !flags.contains(.maskAlternate) {
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
        onCommit?()
    }

    private func cancelSwitching() {
        isSwitching = false
        modifierPollingTask?.cancel()
        modifierPollingTask = nil
        onCancel?()
    }
}
