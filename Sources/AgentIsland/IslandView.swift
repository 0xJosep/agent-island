import SwiftUI

struct IslandView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject private var screenShare = ScreenShare.shared
    @AppStorage("hideWhenScreenShared") private var hideWhenScreenShared = true
    let notchSize: CGSize

    private var isOpen: Bool { store.isOpen }

    private var shy: Bool { screenShare.isShared && hideWhenScreenShared }

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

    private var pillSprite: Sprite {
        if !store.permissions.isEmpty { return .lock }
        if let first = store.sessions.first { return Sprite.forStatus(first.status) }
        return .zzz
    }

    private var closedView: some View {
        HStack {
            if !store.sessions.isEmpty {
                PixelArt(sprite: pillSprite, size: min(notchSize.height - 12, 18))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(store.sessions.prefix(4)) { session in
                    StatusDot(status: session.status)
                        .frame(width: 6, height: 6)
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

            ForEach(Array(store.permissions.enumerated()), id: \.element.id) { position, permission in
                permissionCard(permission, position: position, total: store.permissions.count)
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

            if !store.usage.isEmpty && !shy {
                usageFooter
            }
        }
        .padding(.top, notchSize.height + 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: 440)
    }

    private func permissionCard(_ permission: PermissionItem, position: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PixelArt(sprite: .lock, size: 14)
                Text("Permission: \(permission.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if total > 1 {
                    Text("\(position + 1)/\(total)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.3)))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(sessionName(permission.sessionId))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if !permission.detail.isEmpty && !shy {
                Text(permission.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(3)
            }
            if !permission.preview.isEmpty && !shy {
                previewBox(permission.preview)
            }
            HStack(spacing: 8) {
                actionButton(position == 0 ? "Allow  ⌃⌥A" : "Allow", tint: .green) {
                    store.resolvePermission(id: permission.id, decision: "allow")
                }
                alwaysAllowControl(permission)
                actionButton(position == 0 ? "Deny  ⌃⌥D" : "Deny", tint: .red) {
                    store.resolvePermission(id: permission.id, decision: "deny")
                }
                actionButton("Terminal", tint: .gray) {
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

    private func previewBox(_ preview: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(preview.components(separatedBy: "\n").prefix(9).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(previewColor(line))
                    .lineLimit(1)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 120)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.4)))
    }

    private func previewColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green.opacity(0.85) }
        if line.hasPrefix("-") { return .red.opacity(0.85) }
        return .white.opacity(0.4)
    }

    @ViewBuilder
    private func alwaysAllowControl(_ permission: PermissionItem) -> some View {
        let options = EventServer.scopeOptions(toolName: permission.title, command: permission.command)
        if options.count == 1 {
            actionButton("Always allow", tint: .teal) {
                store.resolvePermission(id: permission.id, decision: options[0].decision)
            }
        } else {
            Menu {
                ForEach(options, id: \.decision) { option in
                    Button(option.label) {
                        store.resolvePermission(id: permission.id, decision: option.decision)
                    }
                }
            } label: {
                Text("Always allow ▾")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.teal.opacity(0.35)))
                    .overlay(Capsule().stroke(Color.teal.opacity(0.6), lineWidth: 1))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
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
            PixelArt(sprite: Sprite.forStatus(session.status), size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName(session))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.source)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.7))
                    if !session.subagentsById.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 8))
                            Text(subagentLabel(session))
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.cyan.opacity(0.8))
                    }
                }
                Text(statusLine(session))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                if session.status == .needsInput {
                    ReplyRow(sessionId: session.id, store: store)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    if store.isSnoozed(session.id) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Text(timestamp(session))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                if let pct = session.contextPct {
                    Text("\(Int(pct))% ctx")
                        .font(.system(size: 9))
                        .foregroundStyle(pct > 80 ? .orange.opacity(0.8) : .white.opacity(0.3))
                }
                if session.status == .working, session.toolCount > 0 {
                    Text("\(session.toolCount) tools")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
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
        .contextMenu {
            Button("Snooze 1 hour") { store.snooze(session.id, minutes: 60) }
            Button("Snooze until tomorrow") { store.snooze(session.id, minutes: 14 * 60) }
            if store.isSnoozed(session.id) {
                Button("Unsnooze") { store.unsnooze(session.id) }
            }
        }
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
        guard let session = store.sessions.first(where: { $0.id == id }) else { return "" }
        return displayName(session)
    }

    private func displayName(_ session: AgentSession) -> String {
        guard shy else { return session.name }
        let index = (store.sessions.map(\.id).sorted().firstIndex(of: session.id) ?? 0) + 1
        return "Session \(index)"
    }

    private func statusLine(_ session: AgentSession) -> String {
        if shy { return "•••" }
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

    private func timestamp(_ session: AgentSession) -> String {
        if session.status == .working, let start = session.turnStartedAt {
            let seconds = Int(Date().timeIntervalSince(start))
            if seconds < 60 { return "\(seconds)s" }
            if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
            return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
        return ago(session.updatedAt)
    }

    private func subagentLabel(_ session: AgentSession) -> String {
        let names = session.subagentsById.values.sorted()
        if names.count <= 2 { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
    }

    private func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

private struct ReplyRow: View {
    let sessionId: String
    let store: SessionStore
    @State private var text = ""
    @State private var failed = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("Reply…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(failed ? Color.red.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if store.sendReply(sessionId, text: trimmed) {
            text = ""
        } else {
            failed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { failed = false }
        }
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
        Rectangle()
            .fill(color)
            .opacity(status == .working && pulsing ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
