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
    var subagentsById: [String: String] = [:]
    var model: String = ""
    var contextPct: Double? = nil
    var termBundleId: String = ""
    var toolCount: Int = 0
    var turnStartedAt: Date? = nil

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
    var agentId: String = ""
}

struct PermissionItem: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let title: String
    let detail: String
    let command: String
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
    private var tombstones: [String: Date] = [:]

    var isOpen: Bool {
        pinnedOpen || !permissions.isEmpty || (hovering && !sessions.isEmpty)
    }

    func apply(_ event: AgentEvent) {
        if ["tool_start", "tool_end", "resumed", "finished", "ended"].contains(event.kind) {
            for item in permissions.filter({ $0.sessionId == event.id }) {
                resolvePermission(id: item.id, decision: "pass")
            }
        }

        if event.kind == "ended" {
            tombstones[event.id] = Date()
            sessions.removeAll { $0.id == event.id }
            permissions.removeAll { $0.sessionId == event.id }
            if sessions.isEmpty { pinnedOpen = false }
            return
        }

        if !sessions.contains(where: { $0.id == event.id }),
           let ended = tombstones[event.id],
           Date().timeIntervalSince(ended) < 30,
           !["idle", "started", "resumed"].contains(event.kind) {
            EventLog.shared.log("event", "tombstone reject \(event.kind) \(event.id.prefix(8))")
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
            session.toolCount = 0
            session.turnStartedAt = Date()
        case "tool_start":
            session.status = .working
            session.activity = event.message
            session.toolCount += 1
            if session.turnStartedAt == nil { session.turnStartedAt = Date() }
        case "tool_end":
            session.activity = ""
        case "finished":
            session.status = .finished
            session.activity = ""
            session.turnStartedAt = nil
            if !event.message.isEmpty { session.message = event.message }
        case "needs_input":
            session.status = .needsInput
            if !event.message.isEmpty { session.message = event.message }
        case "subagent_start":
            let key = event.agentId.isEmpty ? UUID().uuidString : event.agentId
            session.subagentsById[key] = event.message.isEmpty ? "agent" : event.message
        case "subagent_stop":
            session.subagentsById.removeValue(forKey: event.agentId)
        default:
            session.status = .working
        }

        sessions.append(session)
        prune()
        sort()

        switch event.kind {
        case "finished":
            if !frontmostMatches(event.id) {
                EventLog.shared.log("event", "finished pop \(event.id.prefix(8))")
                pop(collapseAfter: Settings.shared.finishedCollapseSeconds)
                chirp(Chiptune.victory)
            } else {
                EventLog.shared.log("event", "finished suppressed frontmost \(event.id.prefix(8))")
            }
        case "needs_input":
            if !frontmostMatches(event.id) {
                EventLog.shared.log("event", "needs_input pop \(event.id.prefix(8))")
                pop(collapseAfter: Settings.shared.needsInputCollapseSeconds)
                chirp(Chiptune.attention)
            } else {
                EventLog.shared.log("event", "needs_input suppressed frontmost \(event.id.prefix(8))")
            }
        case "resumed":
            if permissions.isEmpty { scheduleCollapse(after: 0.6) }
        default:
            break
        }
    }

    func frontmostMatches(_ sessionId: String) -> Bool {
        guard Settings.shared.quietWhenFocused else { return false }
        guard let session = sessions.first(where: { $0.id == sessionId }),
              !session.termBundleId.isEmpty,
              let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return frontmost == session.termBundleId
    }

    func approveTopPermission() {
        guard let top = permissions.first else { return }
        resolvePermission(id: top.id, decision: "allow")
    }

    func denyTopPermission() {
        guard let top = permissions.first else { return }
        resolvePermission(id: top.id, decision: "deny")
    }

    func toggleIsland() {
        collapseWork?.cancel()
        pinnedOpen.toggle()
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
        pinnedOpen = true
        chirp(Chiptune.alarm)
    }

    func resolvePermission(id: String, decision: String) {
        EventLog.shared.log("permission", "resolve \(decision) \(id.prefix(8))")
        permissions.removeAll { $0.id == id }
        permissionHandler?(id, decision)
        for i in sessions.indices where sessions[i].status == .needsInput {
            if !permissions.contains(where: { $0.sessionId == sessions[i].id }) {
                sessions[i].status = .working
            }
        }
        sort()
        if permissions.isEmpty { scheduleCollapse(after: 1.5) }
    }

    func dropPermission(id: String) {
        permissions.removeAll { $0.id == id }
        for i in sessions.indices where sessions[i].status == .needsInput {
            if !permissions.contains(where: { $0.sessionId == sessions[i].id }) {
                sessions[i].status = .working
            }
        }
        if permissions.isEmpty { scheduleCollapse(after: 1.5) }
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

    private func prune() {
        sessions.removeAll { Date().timeIntervalSince($0.updatedAt) > 7200 }
        tombstones = tombstones.filter { Date().timeIntervalSince($0.value) < 60 }
    }

    private func sort() {
        sessions.sort {
            if $0.status != $1.status { return $0.status < $1.status }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func pop(collapseAfter delay: TimeInterval) {
        collapseWork?.cancel()
        pinnedOpen = true
        scheduleCollapse(after: delay)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.permissions.isEmpty { return }
            if self.hovering {
                self.scheduleCollapse(after: 2)
                return
            }
            if self.pinnedOpen {
                EventLog.shared.log("event", "auto-collapse fired")
            }
            self.pinnedOpen = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func chirp(_ melody: [(Double, Double)]) {
        guard Settings.shared.soundsEnabled else { return }
        guard Date().timeIntervalSince(lastSound) > 2 else { return }
        lastSound = Date()
        Chiptune.shared.play(melody)
    }
}
