import XCTest
@testable import AgentIsland

final class AgentSetupTests: XCTestCase {
    private var home: String!
    private let scriptsDir = "/opt/agent-island/scripts"

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "agent-island-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    private var settingsPath: String { home + "/.claude/settings.json" }
    private var codexConfigPath: String { home + "/.codex/config.toml" }

    private func loadSettings() throws -> [String: Any] {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeSettings(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root)
        FileManager.default.createFile(atPath: settingsPath, contents: data)
    }

    func testConnectOnEmptyHomeCreatesAllHooks() throws {
        let status = try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir)
        XCTAssertEqual(status, .connected)

        let root = try loadSettings()
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(AgentSetup.hookEvents))
        XCTAssertEqual(AgentSetup.hookEvents.count, 12)

        let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse", "PermissionRequest"]
        for event in AgentSetup.hookEvents {
            let entries = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            XCTAssertEqual(entries.count, 1, event)
            let entry = entries[0]
            if matcherEvents.contains(event) {
                XCTAssertEqual(entry["matcher"] as? String, "*", event)
            } else {
                XCTAssertNil(entry["matcher"], event)
            }
            let hookList = try XCTUnwrap(entry["hooks"] as? [[String: Any]], event)
            XCTAssertEqual(hookList.count, 1, event)
            let hook = hookList[0]
            XCTAssertEqual(hook["type"] as? String, "command", event)
            if event == "PermissionRequest" {
                XCTAssertEqual(hook["command"] as? String, scriptsDir + "/agent-island-permission.sh")
                XCTAssertEqual(hook["timeout"] as? Int, 600)
            } else {
                XCTAssertEqual(hook["command"] as? String, scriptsDir + "/agent-island-hook.sh", event)
                XCTAssertNil(hook["timeout"], event)
            }
        }

        let statusLine = try XCTUnwrap(root["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, scriptsDir + "/agent-island-statusline.sh")
    }

    func testConnectIsIdempotent() throws {
        try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir)
        let first = try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))
        try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir)
        let second = try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))
        XCTAssertEqual(first, second)
    }

    func testForeignHooksSurviveConnectAndDisconnect() throws {
        let foreignEntry: [String: Any] = [
            "matcher": "Bash",
            "hooks": [["type": "command", "command": "/usr/local/bin/other-tool.sh"]],
        ]
        try writeSettings(["hooks": ["PreToolUse": [foreignEntry]]])

        try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir)
        var hooks = try XCTUnwrap(try loadSettings()["hooks"] as? [String: Any])
        var preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.count, 2)
        XCTAssertTrue(preToolUse.contains { entry in
            ((entry["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "/usr/local/bin/other-tool.sh"
        })

        try AgentSetup.disconnectClaude(home: home)
        hooks = try XCTUnwrap(try loadSettings()["hooks"] as? [String: Any])
        preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.count, 1)
        XCTAssertEqual(
            (preToolUse[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String,
            "/usr/local/bin/other-tool.sh"
        )
    }

    func testDisconnectRemovesAllAgentIslandReferences() throws {
        try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir)
        let status = try AgentSetup.disconnectClaude(home: home)
        XCTAssertEqual(status, .notConnected)
        let text = try String(contentsOfFile: settingsPath, encoding: .utf8)
        XCTAssertFalse(text.contains("agent-island"))
        XCTAssertEqual(AgentSetup.claudeStatus(home: home), .notConnected)
    }

    func testUnparseableSettingsThrowsAndLeavesFileUntouched() throws {
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let garbage = "// not json {"
        try garbage.write(toFile: settingsPath, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentSetup.connectClaude(home: home, scriptsDir: scriptsDir))
        XCTAssertEqual(try String(contentsOfFile: settingsPath, encoding: .utf8), garbage)
    }

    func testCodexNotInstalledWithoutCodexDir() throws {
        XCTAssertEqual(AgentSetup.codexStatus(home: home), .notInstalled)
        XCTAssertEqual(try AgentSetup.connectCodex(home: home, scriptsDir: scriptsDir), .notInstalled)
    }

    func testCodexConnectAppendsNotify() throws {
        try FileManager.default.createDirectory(atPath: home + "/.codex", withIntermediateDirectories: true)
        let original = "model = \"o3\"\n"
        try original.write(toFile: codexConfigPath, atomically: true, encoding: .utf8)

        XCTAssertEqual(AgentSetup.codexStatus(home: home), .notConnected)
        XCTAssertEqual(try AgentSetup.connectCodex(home: home, scriptsDir: scriptsDir), .connected)

        let text = try String(contentsOfFile: codexConfigPath, encoding: .utf8)
        XCTAssertEqual(text, original + "notify = [\"\(scriptsDir)/agent-island-hook.sh\"]\n")
        XCTAssertEqual(AgentSetup.codexStatus(home: home), .connected)

        XCTAssertEqual(try AgentSetup.disconnectCodex(home: home), .notConnected)
        XCTAssertFalse(try String(contentsOfFile: codexConfigPath, encoding: .utf8).contains("agent-island"))
    }

    func testCodexForeignNotifyMeansManualSetup() throws {
        try FileManager.default.createDirectory(atPath: home + "/.codex", withIntermediateDirectories: true)
        let original = "notify = [\"/usr/local/bin/other-notify.sh\"]\n"
        try original.write(toFile: codexConfigPath, atomically: true, encoding: .utf8)

        XCTAssertEqual(AgentSetup.codexStatus(home: home), .manualSetupNeeded)
        XCTAssertEqual(try AgentSetup.connectCodex(home: home, scriptsDir: scriptsDir), .manualSetupNeeded)
        XCTAssertEqual(try String(contentsOfFile: codexConfigPath, encoding: .utf8), original)
    }
}
