import XCTest
@testable import AgentIsland

final class ScopeOptionsTests: XCTestCase {
    func testMultiWordCommandGivesThreeOptions() {
        let options = EventServer.scopeOptions(toolName: "Bash", command: "git push origin main")
        XCTAssertEqual(options.map(\.decision), [
            "allow_rule:Bash(git push *)",
            "allow_rule:Bash(git *)",
            "allow_always",
        ])
    }

    func testSingleWordCommandGivesTwoOptions() {
        let options = EventServer.scopeOptions(toolName: "Bash", command: "ls")
        XCTAssertEqual(options.map(\.decision), [
            "allow_rule:Bash(ls *)",
            "allow_always",
        ])
    }

    func testParenthesizedCommandGivesOnlyAllowAlways() {
        let options = EventServer.scopeOptions(toolName: "Bash", command: "$(whoami) --help")
        XCTAssertEqual(options.map(\.decision), ["allow_always"])
    }

    func testNonBashToolGivesSingleAllowAlways() {
        let options = EventServer.scopeOptions(toolName: "Read", command: "")
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].decision, "allow_always")
        XCTAssertEqual(options[0].label, "Always allow Read")
    }

    func testFlagSecondTokenSkipsTwoTokenOption() {
        let options = EventServer.scopeOptions(toolName: "Bash", command: "git -C x status")
        XCTAssertEqual(options.map(\.decision), [
            "allow_rule:Bash(git *)",
            "allow_always",
        ])
    }

    func testPathSecondTokenSkipsTwoTokenOption() {
        let options = EventServer.scopeOptions(toolName: "Bash", command: "cat /etc/hosts")
        XCTAssertEqual(options.map(\.decision), [
            "allow_rule:Bash(cat *)",
            "allow_always",
        ])
    }
}
