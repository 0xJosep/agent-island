import Foundation

enum FocusMode {
    private static var cached = false
    private static var cachedAt = Date.distantPast

    static func systemFocusActive() -> Bool {
        if Date().timeIntervalSince(cachedAt) < 10 { return cached }
        cachedAt = Date()
        cached = readAssertions()
        return cached
    }

    private static func readAssertions() -> Bool {
        let path = ("~/Library/DoNotDisturb/DB/Assertions.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = json["data"] as? [[String: Any]],
              let first = entries.first,
              let records = first["storeAssertionRecords"] as? [Any]
        else { return false }
        return !records.isEmpty
    }
}
