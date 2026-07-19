import AppKit
import SwiftUI

enum AgentStatus: Int, Equatable, Comparable {
    case needsInput = 0
    case working = 1
    case finished = 2
    case idle = 3

    static func < (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var source: String
    var cwd: String
    var message: String
    var status: AgentStatus
    var updatedAt: Date
    var activity: String = ""
    var subagents: Int = 0
    var model: String = ""
    var contextPct: Double? = nil
    var termBundleId: String = ""

    var name: String {
        cwd.isEmpty ? source : (cwd as NSString).lastPathComponent
    }
}

struct AgentEvent {
    var id: String
    var source: String
    var kind: String
    var message: String
    var cwd: String
    var termBundleId: String = ""
}

struct PermissionItem: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let title: String
    let detail: String
}

struct UsageBar: Equatable {
    let label: String
    let pct: Double
}

final class SessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var permissions: [PermissionItem] = []
    @Published var usage: [UsageBar] = []
    @Published var pinnedOpen = false
    @Published var hovering = false

    var permissionHandler: ((String, String) -> Void)?

    private var collapseWork: DispatchWorkItem?
    private var lastSound = Date.distantPast

    var isOpen: Bool {
        pinnedOpen || !permissions.isEmpty || (hovering && !sessions.isEmpty)
    }

    func apply(_ event: AgentEvent) {
        if event.kind == "ended" {
            sessions.removeAll { $0.id == event.id }
            permissions.removeAll { $0.sessionId == event.id }
            if sessions.isEmpty { pinnedOpen = false }
            return
        }

        var session = sessions.first { $0.id == event.id } ?? AgentSession(
            id: event.id,
            source: event.source,
            cwd: event.cwd,
            message: "",
            status: .idle,
            updatedAt: Date()
        )
        sessions.removeAll { $0.id == event.id }

        session.updatedAt = Date()
        if !event.cwd.isEmpty { session.cwd = event.cwd }
        if !event.termBundleId.isEmpty { session.termBundleId = event.termBundleId }

        switch event.kind {
        case "idle", "started":
            session.status = .idle
        case "resumed":
            session.status = .working
            session.activity = ""
            session.message = ""
        case "tool_start":
            session.status = .working
            session.activity = event.message
        case "tool_end":
            session.activity = ""
        case "finished":
            session.status = .finished
            session.activity = ""
            if !event.message.isEmpty { session.message = event.message }
        case "needs_input":
            session.status = .needsInput
            if !event.message.isEmpty { session.message = event.message }
        case "subagent_start":
            session.subagents += 1
        case "subagent_stop":
            session.subagents = max(0, session.subagents - 1)
        default:
            session.status = .working
        }

        sessions.append(session)
        prune()
        sort()

        switch event.kind {
        case "finished":
            pop(autoCollapse: true)
            play("Glass")
        case "needs_input":
            pop(autoCollapse: false)
            play("Ping")
        case "resumed":
            if !hasAttentionItems { scheduleCollapse(after: 0.6) }
        default:
            break
        }
    }

    func applyStatus(sessionId: String, model: String, contextPct: Double?, usageBars: [UsageBar]) {
        if let i = sessions.firstIndex(where: { $0.id == sessionId }) {
            if !model.isEmpty { sessions[i].model = model }
            if let pct = contextPct { sessions[i].contextPct = pct }
        }
        if !usageBars.isEmpty { usage = usageBars }
    }

    func addPermission(_ item: PermissionItem) {
        permissions.removeAll { $0.id == item.id }
        permissions.append(item)
        if let i = sessions.firstIndex(where: { $0.id == item.sessionId }) {
            sessions[i].status = .needsInput
            sessions[i].updatedAt = Date()
            sort()
        }
        collapseWork?.cancel()
        play("Ping")
    }

    func resolvePermission(id: String, decision: String) {
        permissions.removeAll { $0.id == id }
        permissionHandler?(id, decision)
        for i in sessions.indices where sessions[i].status == .needsInput {
            if !permissions.contains(where: { $0.sessionId == sessions[i].id }) {
                sessions[i].status = .working
            }
        }
        sort()
        if !hasAttentionItems { scheduleCollapse(after: 1.5) }
    }

    func dropPermission(id: String) {
        permissions.removeAll { $0.id == id }
        for i in sessions.indices where sessions[i].status == .needsInput {
            if !permissions.contains(where: { $0.sessionId == sessions[i].id }) {
                sessions[i].status = .working
            }
        }
        if !hasAttentionItems { scheduleCollapse(after: 1.5) }
    }

    func tap(_ session: AgentSession) {
        if session.status == .finished {
            sessions.removeAll { $0.id == session.id }
            if sessions.isEmpty { pinnedOpen = false }
            return
        }
        focusTerminal(session)
    }

    func focusTerminal(_ session: AgentSession) {
        guard !session.termBundleId.isEmpty else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: session.termBundleId).first?.activate()
    }

    private var hasAttentionItems: Bool {
        !permissions.isEmpty || sessions.contains { $0.status == .needsInput }
    }

    private func prune() {
        sessions.removeAll { Date().timeIntervalSince($0.updatedAt) > 7200 }
    }

    private func sort() {
        sessions.sort {
            if $0.status != $1.status { return $0.status < $1.status }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func pop(autoCollapse: Bool) {
        collapseWork?.cancel()
        pinnedOpen = true
        if autoCollapse { scheduleCollapse(after: 6) }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.hasAttentionItems { return }
            if self.hovering {
                self.scheduleCollapse(after: 2)
                return
            }
            self.pinnedOpen = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func play(_ name: String) {
        guard Date().timeIntervalSince(lastSound) > 2 else { return }
        lastSound = Date()
        NSSound(named: name)?.play()
    }
}
