import Foundation
import Network

final class EventServer {
    static let port: UInt16 = 4144

    private let store: SessionStore
    private var listener: NWListener?
    private var pending: [String: NWConnection] = [:]

    init(store: SessionStore) {
        self.store = store
        store.permissionHandler = { [weak self] id, decision in
            self?.respondPermission(id: id, decision: decision)
        }
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

        if path == "/permission" {
            holdPermission(json, connection: connection)
            return
        }

        if path == "/status" {
            processStatus(json)
        } else if let event = Self.parse(json) {
            DispatchQueue.main.async { [store] in
                store.apply(event)
            }
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
        let detail = Self.toolSummary(
            name: toolName,
            input: json["tool_input"] as? [String: Any] ?? [:]
        )
        let item = PermissionItem(
            id: id,
            sessionId: sessionId,
            title: toolName,
            detail: detail
        )
        DispatchQueue.main.async { [weak self, store] in
            self?.pending[id] = connection
            store.addPermission(item)
        }
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                DispatchQueue.main.async {
                    self?.pending.removeValue(forKey: id)
                    self?.store.dropPermission(id: id)
                }
            } else if case .cancelled = state {
                DispatchQueue.main.async {
                    if self?.pending.removeValue(forKey: id) != nil {
                        self?.store.dropPermission(id: id)
                    }
                }
            }
        }
    }

    private func respondPermission(id: String, decision: String) {
        guard let connection = pending.removeValue(forKey: id) else { return }
        let body: String
        switch decision {
        case "allow", "deny":
            body = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\#(decision)"}}}"#
        default:
            body = "{}"
        }
        Self.send(connection, body: body)
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
            case "SubagentStop":
                kind = "subagent_stop"
            case "Stop":
                kind = "finished"
            case "Notification":
                kind = "needs_input"
            case "SessionEnd":
                kind = "ended"
            default:
                return nil
            }
            return AgentEvent(id: id, source: "claude", kind: kind, message: message, cwd: cwd, termBundleId: term)
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
