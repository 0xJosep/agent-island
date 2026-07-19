import XCTest
@testable import AgentIsland

final class EventServerParseTests: XCTestCase {
    private func hookPayload(_ name: String, extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "hook_event_name": name,
            "session_id": "s1",
            "cwd": "/tmp/project",
        ]
        for (key, value) in extra { json[key] = value }
        return json
    }

    func testSessionStartMapsToIdle() {
        let event = EventServer.parse(hookPayload("SessionStart"))
        XCTAssertEqual(event?.kind, "idle")
        XCTAssertEqual(event?.id, "s1")
        XCTAssertEqual(event?.source, "claude")
        XCTAssertEqual(event?.cwd, "/tmp/project")
    }

    func testUserPromptSubmitMapsToResumed() {
        XCTAssertEqual(EventServer.parse(hookPayload("UserPromptSubmit"))?.kind, "resumed")
    }

    func testPreToolUseMapsToToolStartWithDetail() {
        let event = EventServer.parse(hookPayload("PreToolUse", extra: [
            "tool_name": "Bash",
            "tool_input": ["description": "List files", "command": "ls -la"],
        ]))
        XCTAssertEqual(event?.kind, "tool_start")
        XCTAssertEqual(event?.message, "Bash — List files")
    }

    func testPreToolUseWithoutDetailUsesToolName() {
        let event = EventServer.parse(hookPayload("PreToolUse", extra: [
            "tool_name": "Task",
            "tool_input": [String: Any](),
        ]))
        XCTAssertEqual(event?.kind, "tool_start")
        XCTAssertEqual(event?.message, "Task")
    }

    func testPostToolUseMapsToToolEndWithEmptyMessage() {
        let event = EventServer.parse(hookPayload("PostToolUse", extra: [
            "tool_name": "Bash",
            "message": "should be cleared",
        ]))
        XCTAssertEqual(event?.kind, "tool_end")
        XCTAssertEqual(event?.message, "")
    }

    func testStopMapsToFinished() {
        XCTAssertEqual(EventServer.parse(hookPayload("Stop"))?.kind, "finished")
    }

    func testNotificationMapsToNeedsInput() {
        let event = EventServer.parse(hookPayload("Notification", extra: ["message": "Waiting for input"]))
        XCTAssertEqual(event?.kind, "needs_input")
        XCTAssertEqual(event?.message, "Waiting for input")
    }

    func testSessionEndMapsToEnded() {
        XCTAssertEqual(EventServer.parse(hookPayload("SessionEnd"))?.kind, "ended")
    }

    func testSubagentStartCarriesAgentTypeAndAgentId() {
        let event = EventServer.parse(hookPayload("SubagentStart", extra: [
            "agent_type": "Explore",
            "agent_id": "a42",
        ]))
        XCTAssertEqual(event?.kind, "subagent_start")
        XCTAssertEqual(event?.message, "Explore")
        XCTAssertEqual(event?.agentId, "a42")
    }

    func testSubagentStopMapsToSubagentStop() {
        XCTAssertEqual(EventServer.parse(hookPayload("SubagentStop"))?.kind, "subagent_stop")
    }

    func testUnknownHookNameReturnsNil() {
        XCTAssertNil(EventServer.parse(hookPayload("PreCompact")))
    }

    func testTermBundleIdPassthrough() {
        let event = EventServer.parse(hookPayload("Stop", extra: ["term_bundle_id": "com.googlecode.iterm2"]))
        XCTAssertEqual(event?.termBundleId, "com.googlecode.iterm2")
    }

    func testCodexAgentTurnComplete() {
        let event = EventServer.parse([
            "type": "agent-turn-complete",
            "thread-id": "t9",
            "last-assistant-message": "All done",
            "cwd": "/tmp/codex",
            "term_bundle_id": "com.apple.Terminal",
        ])
        XCTAssertEqual(event?.kind, "finished")
        XCTAssertEqual(event?.source, "codex")
        XCTAssertEqual(event?.id, "t9")
        XCTAssertEqual(event?.message, "All done")
        XCTAssertEqual(event?.cwd, "/tmp/codex")
        XCTAssertEqual(event?.termBundleId, "com.apple.Terminal")
    }

    func testGenericSourceTypeEvent() {
        let event = EventServer.parse([
            "type": "working",
            "source": "gemini",
            "id": "g1",
            "message": "thinking",
            "cwd": "/tmp/g",
        ])
        XCTAssertEqual(event?.kind, "working")
        XCTAssertEqual(event?.source, "gemini")
        XCTAssertEqual(event?.id, "g1")
        XCTAssertEqual(event?.message, "thinking")
    }

    func testEmptyPayloadReturnsNil() {
        XCTAssertNil(EventServer.parse([:]))
    }
}
