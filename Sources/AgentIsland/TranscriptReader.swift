import Foundation

enum TranscriptReader {
    struct Message: Equatable {
        let role: String
        let text: String
    }

    static func lastAssistantText(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else { continue }
            guard let message = parse(line: line), message.role == "assistant" else { continue }
            return message.text
        }
        return nil
    }

    static func recentMessages(path: String, limit: Int) -> [Message] {
        guard limit > 0, let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return [] }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        var collected: [Message] = []
        for line in lines.reversed() {
            guard let message = parse(line: line) else { continue }
            collected.append(message)
            if collected.count == limit { break }
        }
        return collected.reversed()
    }

    private static func parse(line: Substring) -> Message? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let entry = object as? [String: Any],
              let type = entry["type"] as? String,
              type == "user" || type == "assistant",
              (entry["isSidechain"] as? Bool) != true,
              (entry["isMeta"] as? Bool) != true,
              let message = entry["message"] as? [String: Any]
        else { return nil }

        let text: String
        if let string = message["content"] as? String {
            text = string
        } else if let blocks = message["content"] as? [[String: Any]] {
            text = blocks
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        } else {
            return nil
        }

        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return nil }
        return Message(role: type, text: cleaned)
    }

    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        var previousBlank = false
        for raw in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousBlank { lines.append("") }
            } else {
                lines.append(line)
            }
            previousBlank = isBlank
        }
        let joined = lines.joined(separator: "\n")
        return joined.count > 2000 ? String(joined.prefix(2000)) : joined
    }
}
