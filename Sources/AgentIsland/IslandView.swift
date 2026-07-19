import SwiftUI

struct IslandView: View {
    @ObservedObject var store: SessionStore
    let notchSize: CGSize

    private var isOpen: Bool { store.isOpen }

    var body: some View {
        island
            .onHover { store.hovering = $0 }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isOpen)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.sessions)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.permissions)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: isOpen ? 22 : 10,
            bottomTrailing: isOpen ? 22 : 10,
            topTrailing: 0
        ))
    }

    private var island: some View {
        Group {
            if isOpen {
                openView
            } else {
                closedView
            }
        }
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)
    }

    private var closedWidth: CGFloat {
        notchSize.width + (store.sessions.isEmpty ? 0 : 72)
    }

    private var closedView: some View {
        HStack {
            if !store.sessions.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(store.sessions.prefix(4)) { session in
                    StatusDot(status: session.status)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: closedWidth, height: notchSize.height)
    }

    private var openView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AGENTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .kerning(1.2)
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 6)

            ForEach(store.permissions) { permission in
                permissionCard(permission)
            }

            if store.sessions.isEmpty && store.permissions.isEmpty {
                Text("No active agents")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ForEach(store.sessions) { session in
                    row(session)
                }
            }

            if !store.usage.isEmpty {
                usageFooter
            }
        }
        .padding(.top, notchSize.height + 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: 440)
    }

    private func permissionCard(_ permission: PermissionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Permission: \(permission.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(sessionName(permission.sessionId))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if !permission.detail.isEmpty {
                Text(permission.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                actionButton("Allow", tint: .green) {
                    store.resolvePermission(id: permission.id, decision: "allow")
                }
                actionButton("Always allow", tint: .teal) {
                    store.resolvePermission(id: permission.id, decision: "allow_always")
                }
                actionButton("Deny", tint: .red) {
                    store.resolvePermission(id: permission.id, decision: "deny")
                }
                actionButton("Use terminal", tint: .gray) {
                    store.resolvePermission(id: permission.id, decision: "pass")
                }
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func actionButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.35)))
                .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func row(_ session: AgentSession) -> some View {
        HStack(spacing: 10) {
            StatusDot(status: session.status)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.source)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.7))
                    if session.subagents > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 8))
                            Text("\(session.subagents)")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.cyan.opacity(0.8))
                    }
                }
                Text(statusLine(session))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ago(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                if let pct = session.contextPct {
                    Text("\(Int(pct))% ctx")
                        .font(.system(size: 9))
                        .foregroundStyle(pct > 80 ? .orange.opacity(0.8) : .white.opacity(0.3))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(session.status == .needsInput ? 0.12 : 0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { store.tap(session) }
    }

    private var usageFooter: some View {
        HStack(spacing: 14) {
            ForEach(store.usage, id: \.label) { bar in
                HStack(spacing: 5) {
                    Text(bar.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(bar.pct > 80 ? Color.orange : Color.white.opacity(0.6))
                                .frame(width: geo.size.width * min(1, bar.pct / 100))
                        }
                    }
                    .frame(width: 44, height: 4)
                    Text("\(Int(bar.pct))%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func sessionName(_ id: String) -> String {
        store.sessions.first { $0.id == id }?.name ?? ""
    }

    private func statusLine(_ session: AgentSession) -> String {
        if session.status == .working && !session.activity.isEmpty {
            return session.activity
        }
        switch session.status {
        case .needsInput:
            return session.message.isEmpty ? "Waiting for your input" : session.message
        case .finished:
            return session.message.isEmpty ? "Task complete" : session.message
        case .working:
            return "Working…"
        case .idle:
            return "Idle"
        }
    }

    private func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

struct StatusDot: View {
    let status: AgentStatus
    @State private var pulsing = false

    private var color: Color {
        switch status {
        case .needsInput: return .red
        case .working: return .orange
        case .finished: return .green
        case .idle: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .opacity(status == .working && pulsing ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
