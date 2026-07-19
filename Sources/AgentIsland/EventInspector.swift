import AppKit
import SwiftUI

struct EventInspectorView: View {
    @ObservedObject private var log = EventLog.shared

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(log.entries.reversed()) { entry in
                        row(entry)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("\(log.entries.count) entries")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy All") { copyAll() }
                Button("Clear") { log.clear() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(entry.category)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(badgeColor(entry.category))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(badgeColor(entry.category).opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                .frame(width: 78, alignment: .leading)
            Text(entry.summary)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func badgeColor(_ category: String) -> Color {
        switch category {
        case "event": return .blue
        case "status": return .gray
        case "permission": return .orange
        case "server": return .purple
        default: return .secondary
        }
    }

    private func copyAll() {
        let text = log.entries
            .map { "\(Self.timeFormatter.string(from: $0.date)) [\($0.category)] \($0.summary)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

final class EventInspectorWindowController {
    static let shared = EventInspectorWindowController()

    private var window: NSWindow?

    private init() {}

    func open() {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Event Inspector"
            newWindow.level = .floating
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(rootView: EventInspectorView())
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
