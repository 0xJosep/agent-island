import AppKit
import Foundation
import Network

final class EventServer {
    static let port: UInt16 = 4144

    private struct PendingPermission {
        let connection: NWConnection
        let toolName: String
    }

    private let store: SessionStore
    private var listener: NWListener?
    private var pending: [String: PendingPermission] = [:]

    init(store: SessionStore) {
        self.store = store
        store.permissionHandler = { [weak self] id, decision in
            self?.respondPermission(id: id, decision: decision)
        }
    }

    static func portFree() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        do {
            listener = try NWListener(using: params)
        } catch {
            NSLog("AgentIsland: failed to bind port \(Self.port): \(error)")
            return
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener?.start(queue: .global(qos: .utility))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let (path, body) = Self.extractRequest(buffer) {
                self.route(path: path, body: body, connection: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func route(path: String, body: Data, connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

        if path == "/quit" {
            EventLog.shared.log("server", "/quit")
            Self.send(connection, body: "bye")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
            return
        }

        if path == "/permission" {
            EventLog.shared.log("server", "/permission")
            holdPermission(json, connection: connection)
            return
        }

        if path == "/log" {
            let dump = DispatchQueue.main.sync {
                EventLog.shared.entries.suffix(120).map { entry in
                    let time = entry.date.formatted(date: .omitted, time: .standard)
                    return "\(time) [\(entry.category)] \(entry.summary)"
                }.joined(separator: "\n")
            }
            Self.send(connection, body: dump.isEmpty ? "(empty)" : dump)
            return
        }

        if path == "/status" {
            processStatus(json)
        } else if let event = Self.parse(json) {
            EventLog.shared.log("event", "\(path) \(event.kind) \(event.id.prefix(8))")
            DispatchQueue.main.async { [store] in
                store.apply(event)
            }
        } else {
            EventLog.shared.log("event", "\(path) unparsed")
        }
        Self.send(connection, body: "ok")
    }

    private func holdPermission(_ json: [String: Any], connection: NWConnection) {
        guard let sessionId = json["session_id"] as? String else {
            Self.send(connection, body: "{}")
            return
        }
        let id = UUID().uuidString
        let toolName = json["tool_name"] as? String ?? "a tool"
        let toolInput = json["tool_input"] as? [String: Any] ?? [:]
        let detail = Self.toolSummary(name: toolName, input: toolInput)
        let command = toolName == "Bash" ? (toolInput["command"] as? String ?? "") : ""
        let item = PermissionItem(
            id: id,
            sessionId: sessionId,
            title: toolName,
            detail: detail,
            command: command,
            preview: Self.toolPreview(name: toolName, input: toolInput)
        )
        DispatchQueue.main.async { [weak self, store] in
            if store.frontmostMatches(sessionId) {
                EventLog.shared.log("permission", "frontmost pass-through \(toolName) \(sessionId.prefix(8))")
                Self.send(connection, body: "{}")
                return
            }
            self?.pending[id] = PendingPermission(connection: connection, toolName: toolName)
            EventLog.shared.log("permission", "created \(id.prefix(8)) \(toolName) \(sessionId.prefix(8))")
            store.addPermission(item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self, self.pending[id] != nil else { return }
            EventLog.shared.log("permission", "expiry 300s fired \(id.prefix(8))")
            self.respondPermission(id: id, decision: "pass")
            self.store.dropPermission(id: id)
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    if self?.pending.removeValue(forKey: id) != nil {
                        EventLog.shared.log("server", "connection \(state) dropped pending \(id.prefix(8))")
                        self?.store.dropPermission(id: id)
                    }
                }
            default:
                break
            }
        }
    }

    private func respondPermission(id: String, decision: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        EventLog.shared.log("permission", "respond \(decision) \(id.prefix(8))")
        let body: String
        switch decision {
        case "allow", "deny":
            body = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\#(decision)"}}}"#
        case "allow_always":
            body = Self.addRuleBody(entry.toolName)
        default:
            if decision.hasPrefix("allow_rule:") {
                body = Self.addRuleBody(String(decision.dropFirst("allow_rule:".count)))
            } else {
                body = "{}"
            }
        }
        Self.send(entry.connection, body: body)
    }

    static func scopeOptions(toolName: String, command: String) -> [(label: String, decision: String)] {
        guard toolName == "Bash" else {
            return [("Always allow \(toolName)", "allow_always")]
        }
        var options: [(label: String, decision: String)] = []
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let safe = { (token: String) in !token.contains("(") && !token.contains(")") }
        if let token1 = tokens.first, safe(token1) {
            if tokens.count > 1 {
                let token2 = tokens[1]
                if safe(token2), !token2.hasPrefix("-"), !token2.contains("/") {
                    options.append(("Always allow \(token1) \(token2) *", "allow_rule:Bash(\(token1) \(token2) *)"))
                }
            }
            options.append(("Always allow \(token1) *", "allow_rule:Bash(\(token1) *)"))
        }
        options.append(("Always allow all Bash", "allow_always"))
        var seen = Set<String>()
        return options.filter { seen.insert($0.decision).inserted }
    }

    private static func addRuleBody(_ ruleContent: String) -> String {
        let decision: [String: Any] = [
            "behavior": "allow",
            "updatedPermissions": [
                [
                    "type": "addRules",
                    "rules": ["allow \(ruleContent)"]
                ]
            ]
        ]
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func processStatus(_ json: [String: Any]) {
        let sessionId = json["session_id"] as? String ?? ""
        let model = ((json["model"] as? [String: Any])?["display_name"] as? String) ?? ""
        var contextPct: Double?
        if let cw = json["context_window"] as? [String: Any] {
            contextPct = (cw["used_percentage"] as? Double) ?? (cw["used_percentage"] as? Int).map(Double.init)
        }
        var bars: [UsageBar] = []
        if let limits = json["rate_limits"] as? [String: Any] {
            for (key, value) in limits.sorted(by: { $0.key < $1.key }) {
                guard let entry = value as? [String: Any] else { continue }
                let pct = (entry["utilization"] as? Double)
                    ?? (entry["utilization"] as? Int).map(Double.init)
                    ?? (entry["used_percentage"] as? Double)
                if let pct {
                    let label = key.replacingOccurrences(of: "_", with: " ")
                    bars.append(UsageBar(label: label, pct: pct))
                }
            }
        }
        let pctText = contextPct.map { String(format: "%.0f%%", $0) } ?? "-"
        EventLog.shared.log("status", "\(sessionId.isEmpty ? "?" : String(sessionId.prefix(8))) ctx \(pctText)")
        guard !sessionId.isEmpty || !bars.isEmpty else { return }
        DispatchQueue.main.async { [store] in
            store.applyStatus(sessionId: sessionId, model: model, contextPct: contextPct, usageBars: Array(bars.prefix(3)))
        }
    }

    private static func send(_ connection: NWConnection, body: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func extractRequest(_ data: Data) -> (String, Data)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        let path = requestParts.count > 1 ? String(requestParts[1]) : "/"
        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        return (path, Data(body.prefix(length)))
    }

    static func toolSummary(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            if let desc = input["description"] as? String, !desc.isEmpty { return desc }
            if let cmd = input["command"] as? String { return String(cmd.prefix(80)) }
        case "Edit", "Write", "Read", "NotebookEdit":
            if let path = input["file_path"] as? String {
                return (path as NSString).lastPathComponent
            }
        case "Grep", "Glob":
            if let pattern = input["pattern"] as? String { return pattern }
        case "WebFetch", "WebSearch":
            if let value = (input["url"] ?? input["query"]) as? String { return value }
        default:
            break
        }
        return ""
    }

    static func toolPreview(name: String, input: [String: Any]) -> String {
        func prefixed(_ text: String, marker: String, max: Int) -> [String] {
            let all = text.components(separatedBy: "\n")
            var out = all.prefix(max).map { marker + $0 }
            if all.count > max { out.append("…") }
            return out
        }
        switch name {
        case "Edit":
            guard let old = input["old_string"] as? String,
                  let new = input["new_string"] as? String else { return "" }
            return (prefixed(old, marker: "- ", max: 4) + prefixed(new, marker: "+ ", max: 4))
                .joined(separator: "\n")
        case "Write":
            guard let content = input["content"] as? String else { return "" }
            return prefixed(content, marker: "+ ", max: 6).joined(separator: "\n")
        case "NotebookEdit":
            guard let source = input["new_source"] as? String else { return "" }
            return prefixed(source, marker: "+ ", max: 6).joined(separator: "\n")
        default:
            return ""
        }
    }

    static func parse(_ json: [String: Any]) -> AgentEvent? {
        if let hookName = json["hook_event_name"] as? String {
            let id = json["session_id"] as? String ?? "claude"
            let cwd = json["cwd"] as? String ?? ""
            let term = json["term_bundle_id"] as? String ?? ""
            let toolName = json["tool_name"] as? String ?? ""
            let toolInput = json["tool_input"] as? [String: Any] ?? [:]

            let kind: String
            var message = json["message"] as? String ?? ""
            switch hookName {
            case "SessionStart":
                kind = "idle"
            case "UserPromptSubmit":
                kind = "resumed"
            case "PreToolUse":
                kind = "tool_start"
                let detail = toolSummary(name: toolName, input: toolInput)
                message = detail.isEmpty ? toolName : "\(toolName) — \(detail)"
            case "PostToolUse":
                kind = "tool_end"
                message = ""
            case "SubagentStart":
                kind = "subagent_start"
                message = json["agent_type"] as? String ?? ""
            case "SubagentStop":
                kind = "subagent_stop"
            case "Stop":
                kind = "finished"
            case "Notification":
                kind = "needs_input"
            case "TaskCreated", "TaskCompleted":
                guard json["session_id"] is String else { return nil }
                kind = hookName == "TaskCreated" ? "task_created" : "task_completed"
                message = ""
            case "SessionEnd":
                kind = "ended"
            default:
                return nil
            }
            return AgentEvent(
                id: id,
                source: "claude",
                kind: kind,
                message: message,
                cwd: cwd,
                termBundleId: term,
                agentId: json["agent_id"] as? String ?? "",
                transcriptPath: json["transcript_path"] as? String ?? ""
            )
        }

        if let type = json["type"] as? String, type == "agent-turn-complete" {
            return AgentEvent(
                id: json["thread-id"] as? String ?? json["turn-id"] as? String ?? "codex",
                source: "codex",
                kind: "finished",
                message: json["last-assistant-message"] as? String ?? "",
                cwd: json["cwd"] as? String ?? "",
                termBundleId: json["term_bundle_id"] as? String ?? ""
            )
        }

        if let kind = json["type"] as? String {
            let source = json["source"] as? String ?? "agent"
            return AgentEvent(
                id: json["id"] as? String ?? source,
                source: source,
                kind: kind,
                message: json["message"] as? String ?? "",
                cwd: json["cwd"] as? String ?? "",
                termBundleId: json["term_bundle_id"] as? String ?? ""
            )
        }
        return nil
    }
}
