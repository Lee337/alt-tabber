import AppKit

@MainActor
protocol ScriptingDelegate: AnyObject {
    func executeCommand(_ name: String, arguments: [String: Any]) async throws -> String
}
@MainActor
final class ScriptingBridge {
    static let shared = ScriptingBridge()
    weak var delegate: (any ScriptingDelegate)?
    func execute(_ name: String, json: String) async throws -> String {
        guard let data = json.data(using: .utf8), let arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScriptingError.invalidArguments
        }
        guard let delegate else { throw ScriptingError.unavailable }
        return try await delegate.executeCommand(name, arguments: arguments)
    }
}
enum ScriptingError: Error, LocalizedError {
    case invalidArguments, unavailable, targetNotFound, unknownCommand, actionFailed(WindowActionResult)
    var errorDescription: String? {
        switch self {
        case .invalidArguments: "Arguments must be a JSON object with valid values."
        case .unavailable: "AltTabber is not ready."
        case .targetNotFound: "The requested application or window is no longer available."
        case .unknownCommand: "Unknown command. Use help for supported commands."
        case .actionFailed(let result): "Window action failed: \(result.rawValue)."
        }
    }
}

enum ScriptingAlias {
    static func resolve(name: String, direct: String?, json: String) throws -> (String, String) {
        if name == "perform command" {
            guard let direct, !direct.isEmpty else { throw ScriptingError.invalidArguments }
            return (direct, json)
        }
        let commands = [
            "show preview": "show-preview", "hide preview": "hide-preview", "show switcher": "show-switcher",
            "list windows": "list-windows", "get windows": "list-windows", "list apps": "list-apps",
            "get active window": "active-window", "get window": "get-window", "get help": "help"
        ]
        let actions = [
            "focus window": "focus", "minimize window": "minimize", "close window": "close",
            "maximize window": "maximize", "hide window": "hide", "toggle fullscreen": "fullscreen",
            "center window": "center", "position window": ""
        ]
        guard let data = json.data(using: .utf8),
              var arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScriptingError.invalidArguments
        }
        let command: String
        if let mapped = commands[name] { command = mapped }
        else if let action = actions[name] {
            command = "window-action"
            if !action.isEmpty { arguments["action"] = action }
        } else { throw ScriptingError.unknownCommand }
        if let direct, !direct.isEmpty {
            if command == "show-preview" { arguments["app"] = direct }
            else if command == "window-action" || command == "get-window" {
                if direct == "active" { arguments["window"] = "active" }
                else if let id = Int(direct), id > 0 { arguments["window"] = id }
                else { throw ScriptingError.invalidArguments }
            } else if command == "list-windows" || command == "list-apps" { arguments["app"] = direct }
        }
        return (command, String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self))
    }
}
@objc(AltTabberScriptCommand)
final class AltTabberScriptCommand: NSScriptCommand, @unchecked Sendable {
    override func performDefaultImplementation() -> Any? {
        let name = commandDescription.commandName
        let direct = directParameter as? String
        let arguments = evaluatedArguments?["arguments"] as? String ?? "{}"
        suspendExecution()
        Task { @MainActor in
            do {
                let resolved = try ScriptingAlias.resolve(name: name, direct: direct, json: arguments)
                let result = try await ScriptingBridge.shared.execute(resolved.0, json: resolved.1)
                resumeExecution(withResult: result)
            } catch {
                scriptErrorNumber = -1708; scriptErrorString = error.localizedDescription
                resumeExecution(withResult: nil)
            }
        }
        return nil
    }
}

struct ScriptWindow: Codable {
    let id: UInt32
    let pid: Int32
    let app: String
    let title: String
    let bundleIdentifier: String?
    let frame: ScriptFrame
    let displayID: UInt32?
    let spaceIDs: [UInt64]?
    let minimized: Bool
    let hidden: Bool
    let fullscreen: Bool
    var previewPNG: String? = nil
    let createdAt: Date
    let lastUsedAt: Date
    init(_ window: WindowItem) {
        id = window.id; pid = window.processID; app = window.appName; title = window.title
        bundleIdentifier = window.bundleIdentifier; frame = ScriptFrame(window.bounds)
        displayID = window.displayID; spaceIDs = window.spaceIDs
        minimized = window.isMinimized; hidden = window.isHidden; fullscreen = window.isFullscreen
        createdAt = window.createdAt; lastUsedAt = window.lastUsedAt
    }
}
struct ScriptFrame: Codable {
    let x: Double; let y: Double; let width: Double; let height: Double
    init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
}
struct ScriptApp: Codable {
    let pid: Int32; let name: String; let bundleIdentifier: String?; let windowCount: Int
}
enum ScriptJSON {
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
