import XCTest
@testable import AgentIsland

final class TranscriptReaderTests: XCTestCase {
    private var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "transcript-reader-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func write(_ lines: [String]) -> String {
        let path = dir + "/" + UUID().uuidString + ".jsonl"
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func assistantLine(blocks: [[String: Any]]) -> String {
        line(type: "assistant", content: blocks)
    }

    private func userLine(content: Any) -> String {
        line(type: "user", content: content)
    }

    private func line(type: String, content: Any) -> String {
        let entry: [String: Any] = [
            "type": type,
            "uuid": UUID().uuidString,
            "timestamp": "2026-07-19T00:00:00.000Z",
            "message": ["role": type, "content": content],
        ]
        let data = try! JSONSerialization.data(withJSONObject: entry)
        return String(decoding: data, as: UTF8.self)
    }

    func testLastAssistantTextReturnsMostRecentText() {
        let path = write([
            userLine(content: "hello"),
            assistantLine(blocks: [["type": "text", "text": "first reply"]]),
            userLine(content: "again"),
            assistantLine(blocks: [["type": "text", "text": "second reply"]]),
        ])
        XCTAssertEqual(TranscriptReader.lastAssistantText(path: path), "second reply")
    }

    func testLastAssistantTextSkipsToolUseAndThinkingOnlyLines() {
        let path = write([
            assistantLine(blocks: [["type": "text", "text": "real answer"]]),
            assistantLine(blocks: [["type": "thinking", "thinking": "pondering"]]),
            assistantLine(blocks: [["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "ls"]]]),
        ])
        XCTAssertEqual(TranscriptReader.lastAssistantText(path: path), "real answer")
    }

    func testLastAssistantTextJoinsMultipleTextBlocks() {
        let path = write([
            assistantLine(blocks: [
                ["type": "text", "text": "part one"],
                ["type": "tool_use", "id": "t1", "name": "Bash", "input": [:]],
                ["type": "text", "text": "part two"],
            ]),
        ])
        XCTAssertEqual(TranscriptReader.lastAssistantText(path: path), "part one\npart two")
    }

    func testLastAssistantTextIgnoresNonMessageLines() {
        let path = write([
            assistantLine(blocks: [["type": "text", "text": "answer"]]),
            "{\"type\":\"last-prompt\",\"lastPrompt\":\"x\",\"leafUuid\":\"y\",\"sessionId\":\"z\"}",
            "{\"type\":\"file-history-snapshot\",\"sessionId\":\"z\"}",
            "{\"type\":\"system\",\"content\":\"note\"}",
        ])
        XCTAssertEqual(TranscriptReader.lastAssistantText(path: path), "answer")
    }

    func testRecentMessagesChronologicalOrderAndRoles() {
        let path = write([
            userLine(content: "question one"),
            assistantLine(blocks: [["type": "text", "text": "answer one"]]),
            userLine(content: [["type": "text", "text": "question two"]]),
            assistantLine(blocks: [["type": "text", "text": "answer two"]]),
        ])
        let messages = TranscriptReader.recentMessages(path: path, limit: 10)
        XCTAssertEqual(messages, [
            TranscriptReader.Message(role: "user", text: "question one"),
            TranscriptReader.Message(role: "assistant", text: "answer one"),
            TranscriptReader.Message(role: "user", text: "question two"),
            TranscriptReader.Message(role: "assistant", text: "answer two"),
        ])
    }

    func testRecentMessagesSkipsToolResultOnlyUserLines() {
        let path = write([
            userLine(content: "real question"),
            assistantLine(blocks: [["type": "tool_use", "id": "t1", "name": "Read", "input": [:]]]),
            userLine(content: [["type": "tool_result", "tool_use_id": "t1", "content": "file contents"]]),
            assistantLine(blocks: [["type": "text", "text": "summary"]]),
        ])
        let messages = TranscriptReader.recentMessages(path: path, limit: 10)
        XCTAssertEqual(messages, [
            TranscriptReader.Message(role: "user", text: "real question"),
            TranscriptReader.Message(role: "assistant", text: "summary"),
        ])
    }

    func testRecentMessagesRespectsLimit() {
        let path = write((1...6).map { userLine(content: "message \($0)") })
        let messages = TranscriptReader.recentMessages(path: path, limit: 2)
        XCTAssertEqual(messages.map(\.text), ["message 5", "message 6"])
    }

    func testMalformedLinesAreSkipped() {
        let path = write([
            "not json at all",
            "{\"type\":\"assistant\"",
            "{\"type\":\"assistant\",\"message\":null}",
            "42",
            assistantLine(blocks: [["type": "text", "text": "survived"]]),
            "{broken",
        ])
        XCTAssertEqual(TranscriptReader.lastAssistantText(path: path), "survived")
        XCTAssertEqual(TranscriptReader.recentMessages(path: path, limit: 10).count, 1)
    }

    func testMissingFileReturnsNilAndEmpty() {
        let path = dir + "/does-not-exist.jsonl"
        XCTAssertNil(TranscriptReader.lastAssistantText(path: path))
        XCTAssertEqual(TranscriptReader.recentMessages(path: path, limit: 5), [])
    }

    func testEmptyFileReturnsNilAndEmpty() {
        let path = write([])
        XCTAssertNil(TranscriptReader.lastAssistantText(path: path))
        XCTAssertEqual(TranscriptReader.recentMessages(path: path, limit: 5), [])
    }

    func testZeroLimitReturnsEmpty() {
        let path = write([userLine(content: "hi")])
        XCTAssertEqual(TranscriptReader.recentMessages(path: path, limit: 0), [])
    }

    func testTextIsTrimmedCollapsedAndCapped() {
        let long = String(repeating: "a", count: 3000)
        let path = write([
            assistantLine(blocks: [["type": "text", "text": "\n\n  line one\n\n\n\nline two\n\n"]]),
            userLine(content: long),
        ])
        let messages = TranscriptReader.recentMessages(path: path, limit: 10)
        XCTAssertEqual(messages.first?.text, "line one\n\nline two")
        XCTAssertEqual(messages.last?.text.count, 2000)
    }

    func testRealTranscriptSmoke() throws {
        let projects = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projects) else {
            throw XCTSkip("no ~/.claude/projects directory")
        }
        var newest: (path: String, date: Date)?
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".jsonl") else { continue }
            let full = projects + "/" + relative
            let attributes = try? fm.attributesOfItem(atPath: full)
            let date = (attributes?[.modificationDate] as? Date) ?? .distantPast
            if newest == nil || date > newest!.date {
                newest = (full, date)
            }
        }
        guard let transcript = newest else {
            throw XCTSkip("no transcripts found")
        }
        _ = TranscriptReader.lastAssistantText(path: transcript.path)
        let messages = TranscriptReader.recentMessages(path: transcript.path, limit: 5)
        XCTAssertLessThanOrEqual(messages.count, 5)
        for message in messages {
            XCTAssertTrue(message.role == "user" || message.role == "assistant")
            XCTAssertFalse(message.text.isEmpty)
        }
    }
}
