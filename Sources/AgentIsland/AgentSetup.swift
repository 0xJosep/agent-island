import Foundation

enum AgentSetup {
    enum Status {
        case connected
        case notConnected
        case notInstalled
        case manualSetupNeeded
    }

    static var defaultHome: String {
        ProcessInfo.processInfo.environment["AGENT_ISLAND_HOME"] ?? NSHomeDirectory()
    }

    static let hookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart",
        "SubagentStop", "Stop", "Notification", "SessionEnd", "PermissionRequest",
        "TaskCreated", "TaskCompleted",
    ]

    private static let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse", "PermissionRequest"]

    static var scriptsDirectory: String {
        if Bundle.main.bundlePath.hasSuffix(".app"), let resources = Bundle.main.resourcePath {
            return resources + "/scripts"
        }
        let executable = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        return executable
            .deletingLastPathComponent()
            .appendingPathComponent("../../scripts")
            .standardizedFileURL
            .path
    }

    static func claudeStatus(home: String = defaultHome) -> Status {
        guard let hooks = loadSettings(home: home)["hooks"] as? [String: Any] else { return .notConnected }
        for value in hooks.values {
            guard let entries = value as? [[String: Any]] else { continue }
            if entries.contains(where: containsAgentIsland) { return .connected }
        }
        return .notConnected
    }

    @discardableResult
    static func connectClaude(home: String = defaultHome, scriptsDir: String = scriptsDirectory) throws -> Status {
        var root = try loadSettingsStrict(home: home)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if !entries.contains(where: containsAgentIsland) {
                entries.append(hookEntry(event: event, scriptsDir: scriptsDir))
            }
            hooks[event] = entries
        }
        root["hooks"] = hooks
        let statusCommand = (root["statusLine"] as? [String: Any])?["command"] as? String
        if statusCommand == nil || statusCommand?.contains("agent-island") == true || statusCommand?.contains("vibe-island") == true {
            root["statusLine"] = ["type": "command", "command": scriptsDir + "/agent-island-statusline.sh"]
        }
        try writeSettings(root, home: home)
        return .connected
    }

    @discardableResult
    static func disconnectClaude(home: String = defaultHome) throws -> Status {
        guard FileManager.default.fileExists(atPath: claudeSettingsPath(home: home)) else { return .notConnected }
        var root = try loadSettingsStrict(home: home)
        if var hooks = root["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard let entries = value as? [[String: Any]] else { continue }
                let kept: [[String: Any]] = entries.compactMap { entry in
                    guard let hookList = entry["hooks"] as? [[String: Any]] else { return entry }
                    let survivors = hookList.filter { ($0["command"] as? String)?.contains("agent-island") != true }
                    if survivors.isEmpty, survivors.count != hookList.count { return nil }
                    var entry = entry
                    entry["hooks"] = survivors
                    return entry
                }
                if kept.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = kept
                }
            }
            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }
        }
        if let statusCommand = (root["statusLine"] as? [String: Any])?["command"] as? String,
           statusCommand.contains("agent-island") {
            root.removeValue(forKey: "statusLine")
        }
        try writeSettings(root, home: home)
        return .notConnected
    }

    static func codexStatus(home: String = defaultHome) -> Status {
        guard codexInstalled(home: home) else { return .notInstalled }
        let lines = codexLines(home: home)
        if lines.contains(where: isAgentIslandNotify) { return .connected }
        if lines.contains(where: isNotifyLine) { return .manualSetupNeeded }
        return .notConnected
    }

    @discardableResult
    static func connectCodex(home: String = defaultHome, scriptsDir: String = scriptsDirectory) throws -> Status {
        guard codexInstalled(home: home) else { return .notInstalled }
        let lines = codexLines(home: home)
        if lines.contains(where: isAgentIslandNotify) { return .connected }
        if lines.contains(where: isNotifyLine) { return .manualSetupNeeded }
        var text = (try? String(contentsOfFile: codexConfigPath(home: home), encoding: .utf8)) ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += "notify = [\"\(scriptsDir)/agent-island-hook.sh\"]\n"
        try text.write(toFile: codexConfigPath(home: home), atomically: true, encoding: .utf8)
        return .connected
    }

    @discardableResult
    static func disconnectCodex(home: String = defaultHome) throws -> Status {
        guard codexInstalled(home: home) else { return .notInstalled }
        let path = codexConfigPath(home: home)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .notConnected }
        let kept = text.components(separatedBy: "\n").filter { !isAgentIslandNotify($0) }
        try kept.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return .notConnected
    }

    private static func claudeSettingsPath(home: String) -> String {
        home + "/.claude/settings.json"
    }

    private static func codexConfigPath(home: String) -> String {
        home + "/.codex/config.toml"
    }

    private static func codexInstalled(home: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: home + "/.codex", isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func codexLines(home: String) -> [String] {
        guard let text = try? String(contentsOfFile: codexConfigPath(home: home), encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
    }

    private static func isAgentIslandNotify(_ line: String) -> Bool {
        line.contains("notify") && line.contains("agent-island")
    }

    private static func isNotifyLine(_ line: String) -> Bool {
        line.range(of: #"^\s*notify\s*="#, options: .regularExpression) != nil
    }

    private static func loadSettings(home: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath(home: home)),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return root
    }

    private static func loadSettingsStrict(home: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath(home: home)) else { return [:] }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "AgentSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "settings.json is not plain JSON (comments?) — add the hooks manually"
            ])
        }
        return root
    }

    private static func writeSettings(_ root: [String: Any], home: String) throws {
        let path = claudeSettingsPath(home: home)
        let backup = path + ".agent-island-backup"
        if FileManager.default.fileExists(atPath: path), !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.copyItem(atPath: path, toPath: backup)
        }
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func hookEntry(event: String, scriptsDir: String) -> [String: Any] {
        var hook: [String: Any] = ["type": "command"]
        if event == "PermissionRequest" {
            hook["command"] = scriptsDir + "/agent-island-permission.sh"
            hook["timeout"] = 600
        } else {
            hook["command"] = scriptsDir + "/agent-island-hook.sh"
        }
        var entry: [String: Any] = ["hooks": [hook]]
        if matcherEvents.contains(event) {
            entry["matcher"] = "*"
        }
        return entry
    }

    private static func containsAgentIsland(_ entry: [String: Any]) -> Bool {
        let hookList = entry["hooks"] as? [[String: Any]] ?? []
        return hookList.contains { ($0["command"] as? String)?.contains("agent-island") == true }
    }
}
