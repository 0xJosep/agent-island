import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let summary: String
}

final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published var entries: [LogEntry] = []

    private let cap = 300

    private init() {}

    func log(_ category: String, _ summary: String) {
        let text = summary.count > 120 ? String(summary.prefix(120)) + "…" : summary
        DispatchQueue.main.async {
            self.entries.append(LogEntry(date: Date(), category: category, summary: text))
            if self.entries.count > self.cap {
                self.entries.removeFirst(self.entries.count - self.cap)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}
