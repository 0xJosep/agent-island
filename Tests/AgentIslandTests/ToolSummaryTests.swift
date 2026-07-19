import XCTest
@testable import AgentIsland

final class ToolSummaryTests: XCTestCase {
    func testBashPrefersDescriptionOverCommand() {
        let summary = EventServer.toolSummary(
            name: "Bash",
            input: ["description": "List files", "command": "ls -la"]
        )
        XCTAssertEqual(summary, "List files")
    }

    func testBashFallsBackToCommand() {
        XCTAssertEqual(EventServer.toolSummary(name: "Bash", input: ["command": "git status"]), "git status")
    }

    func testBashTruncatesLongCommand() {
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(EventServer.toolSummary(name: "Bash", input: ["command": long]).count, 80)
    }

    func testEditUsesBasename() {
        let summary = EventServer.toolSummary(
            name: "Edit",
            input: ["file_path": "/Users/me/project/Sources/File.swift"]
        )
        XCTAssertEqual(summary, "File.swift")
    }

    func testReadUsesBasename() {
        XCTAssertEqual(EventServer.toolSummary(name: "Read", input: ["file_path": "/a/b/c.txt"]), "c.txt")
    }

    func testGrepUsesPattern() {
        XCTAssertEqual(EventServer.toolSummary(name: "Grep", input: ["pattern": "func parse"]), "func parse")
    }

    func testUnknownToolReturnsEmpty() {
        XCTAssertEqual(EventServer.toolSummary(name: "SomethingElse", input: ["command": "x"]), "")
    }
}
