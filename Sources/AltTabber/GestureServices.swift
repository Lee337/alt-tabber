import AppKit

struct SwipePoint: Equatable {
    let id: Int
    let x: Double
    let y: Double
}
enum SwipeIntent: Equatable { case open, forward, backward, commit }
struct SwipeDetector {
    private var origin: [Int: SwipePoint] = [:]
    private var opened = false
    mutating func update(_ points: [SwipePoint], fingers: Int, threshold: Double = 0.08, vertical: Bool = false) -> SwipeIntent? {
        if points.count < fingers {
            let commit = opened && points.isEmpty
            origin = [:]; opened = false
            return commit ? .commit : nil
        }
        guard points.count == fingers else { origin = [:]; opened = false; return nil }
        if origin.count != fingers || !points.allSatisfy({ origin[$0.id] != nil }) {
            origin = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) }); return nil
        }
        let dx = points.map { vertical ? $0.y - origin[$0.id]!.y : $0.x - origin[$0.id]!.x }.reduce(0, +) / Double(fingers)
        let dy = points.map { vertical ? $0.x - origin[$0.id]!.x : $0.y - origin[$0.id]!.y }.reduce(0, +) / Double(fingers)
        guard abs(dx) >= threshold, abs(dx) > abs(dy) * 1.5 else { return nil }
        origin = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        if !opened { opened = true; return .open }
        return dx > 0 ? .forward : .backward
    }
}

@MainActor
final class GlobalSwipeService {
    var onIntent: ((SwipeIntent) -> Void)?
    private var monitor: OverlayInputMonitor?
    private var detector = SwipeDetector()
    private var identities: [AnyHashable: Int] = [:]
    var fingers = 3
    var vertical = false
    var isAvailable = false
    func start() {
        stop()
        let monitor = OverlayInputMonitor()
        monitor.customMask = NSEvent.EventTypeMask.gesture.rawValue
        monitor.onEvent = { [weak self] _, cgEvent in
            guard let self, let event = NSEvent(cgEvent: cgEvent) else { return false }
            let all = event.allTouches().filter { $0.type == .indirect }
            guard !all.isEmpty else { return false }
            let touches = all.filter { NSTouch.Phase.touching.contains($0.phase) && !$0.isResting }
            let points = touches.map { touch -> SwipePoint in
                let key = AnyHashable(touch.identity as! NSObject)
                if identities[key] == nil { identities[key] = identities.count + 1 }
                return SwipePoint(id: identities[key]!, x: touch.normalizedPosition.x, y: touch.normalizedPosition.y)
            }
            if let intent = detector.update(points, fingers: fingers, vertical: vertical) { onIntent?(intent) }
            if points.isEmpty { identities = [:] }
            return false
        }
        isAvailable = monitor.start(); self.monitor = monitor
    }
    func stop() { monitor?.stop(); monitor = nil; isAvailable = false; detector = SwipeDetector(); identities = [:] }
}

enum DockLockGeometry {
    static func constrained(_ point: CGPoint, screens: [CGRect], lockedIndex: Int, orientation: String, override: Bool) -> CGPoint {
        guard !override, screens.indices.contains(lockedIndex), screens.count > 1 else { return point }
        for (index, frame) in screens.enumerated() where index != lockedIndex && frame.contains(point) {
            let exposed: Bool
            switch orientation {
            case "left":
                exposed = !screens.enumerated().contains { $0.offset != index && abs($0.element.maxX - frame.minX) < 2 && $0.element.minY < point.y && $0.element.maxY > point.y }
                if exposed && point.x < frame.minX + 3 { return CGPoint(x: frame.minX + 4, y: point.y) }
            case "right":
                exposed = !screens.enumerated().contains { $0.offset != index && abs($0.element.minX - frame.maxX) < 2 && $0.element.minY < point.y && $0.element.maxY > point.y }
                if exposed && point.x > frame.maxX - 3 { return CGPoint(x: frame.maxX - 4, y: point.y) }
            default:
                exposed = !screens.enumerated().contains { $0.offset != index && abs($0.element.minY - frame.maxY) < 2 && $0.element.minX < point.x && $0.element.maxX > point.x }
                if exposed && point.y > frame.maxY - 3 { return CGPoint(x: point.x, y: frame.maxY - 4) }
            }
        }
        return point
    }
}

@MainActor
final class TitleBarScrollService {
    private var restore: [String: (CGRect, Date)] = [:]
    func handle(_ event: CGEvent, actions: WindowActionService, windows: WindowService, settings: FeatureSettings) -> Bool {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        guard phase == 1 || phase == 0,
              let id = windows.focusedWindowID(), let item = windows.visibleWindows().first(where: { $0.id == id }) else { return false }
        let point = event.location
        guard point.x >= item.bounds.minX, point.x <= item.bounds.maxX,
              point.y >= item.bounds.minY, point.y <= item.bounds.minY + 28 else { return false }
        let entry = SelectionEntry.window(item)
        let now = Date()
        if let (original, changedAt) = restore[entry.id], now.timeIntervalSince(changedAt) <= settings.titleBarRestoreInterval {
            _ = actions.resize(entry, to: original); restore[entry.id] = nil; return true
        }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let screen = NSScreen.screens.first(where: { $0.displayID == item.displayID }) ?? NSScreen.main else { return false }
        let visible = WindowGeometry.accessibilityFrame(screen.visibleFrame, desktopTop: desktopTop)
        let width = visible.width * settings.titleBarWidthScale
        let height = visible.height * settings.titleBarHeightScale
        let centered = CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        restore[entry.id] = (item.bounds, now)
        _ = actions.resize(entry, to: delta > 0 ? visible : centered)
        return true
    }

}

struct ShakeDetector {
    private var previousX: Double?
    private var direction = 0.0
    private var reversals = 0
    private var began = 0.0
    private var cooldownUntil = 0.0
    mutating func update(x: Double, at time: Double) -> Bool {
        defer { previousX = x }
        guard time >= cooldownUntil, let previousX else { return false }
        let delta = x - previousX
        guard abs(delta) > 8 else { return false }
        if time - began > 0.6 { began = time; reversals = 0; direction = delta }
        if delta * direction < 0 { reversals += 1; direction = delta }
        if reversals >= 4 { reversals = 0; cooldownUntil = time + 2; return true }
        return false
    }
}
