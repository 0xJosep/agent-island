import AppKit
import Foundation

enum TerminalBridge {
    static func focusTab(bundleId: String, cwd: String) -> Bool {
        perform(bundleId: bundleId, cwd: cwd, text: nil)
    }

    static func writeText(bundleId: String, cwd: String, text: String) -> Bool {
        perform(bundleId: bundleId, cwd: cwd, text: text)
    }

    private static func perform(bundleId: String, cwd: String, text: String?) -> Bool {
        guard isRunning(bundleId) else { return false }
        switch bundleId {
        case "com.googlecode.iterm2":
            return itermPerform(cwd: cwd, text: text)
        case "com.apple.Terminal":
            return terminalPerform(cwd: cwd, text: text)
        default:
            return false
        }
    }

    private static func itermPerform(cwd: String, text: String?) -> Bool {
        var actions = ["select w", "select t", "select s"]
        if let text {
            actions.append("tell s to write text \"\(escaped(text))\"")
        }
        actions.append("activate")
        let source = """
        set theCwd to "\(escaped(cwd))"
        set theCwdPrefix to "\(escaped(prefixForm(cwd)))"
        tell application "iTerm2"
            repeat with modeIdx from 1 to 2
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set p to ""
                            try
                                tell s to set p to (variable named "path")
                            end try
                            if p is missing value then set p to ""
                            if p is "" then
                                try
                                    tell s to set p to (variable named "session.path")
                                end try
                                if p is missing value then set p to ""
                            end if
                            if p is not "" then
                                set isMatch to false
                                if modeIdx is 1 then
                                    if p is theCwd then set isMatch to true
                                else
                                    if p starts with theCwdPrefix then set isMatch to true
                                end if
                                if isMatch then
                                    \(actions.joined(separator: "\n                                    "))
                                    return "OK"
                                end if
                            end if
                        end repeat
                    end repeat
                end repeat
            end repeat
        end tell
        return "NO"
        """
        return runAppleScript(source) == "OK"
    }

    private static func terminalPerform(cwd: String, text: String?) -> Bool {
        guard let devTty = terminalTtyMatching(cwd: cwd) else { return false }
        var actions = ["set selected of t to true", "set frontmost of w to true"]
        if let text {
            actions.append("do script \"\(escaped(text))\" in t")
        }
        actions.append("activate")
        let source = """
        set theTty to "\(escaped(devTty))"
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is theTty then
                            \(actions.joined(separator: "\n                            "))
                            return "OK"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "NO"
        """
        return runAppleScript(source) == "OK"
    }

    private static func terminalTtyMatching(cwd: String) -> String? {
        let listSource = """
        set out to ""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & (tty of t) & linefeed
                    end try
                end repeat
            end repeat
        end tell
        return out
        """
        guard let ttyOutput = runAppleScript(listSource) else { return nil }
        let devTtys = ttyOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("/dev/") }
        guard !devTtys.isEmpty else { return nil }
        let shortNames = Set(devTtys.map { String($0.dropFirst("/dev/".count)) })

        guard let psOut = runCommand("/bin/ps", ["-axo", "pid=,tty="]) else { return nil }
        var ttyToPids: [String: [String]] = [:]
        for line in psOut.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, shortNames.contains(parts[1]) else { continue }
            ttyToPids[parts[1], default: []].append(parts[0])
        }
        let allPids = ttyToPids.values.flatMap { $0 }
        guard !allPids.isEmpty else { return nil }

        let lsofArgs = ["-a", "-d", "cwd", "-p", allPids.joined(separator: ","), "-Fn"]
        guard let lsofOut = runCommand("/usr/sbin/lsof", lsofArgs) else { return nil }
        var pidToCwd: [String: String] = [:]
        var currentPid = ""
        for line in lsofOut.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") {
                currentPid = String(line.dropFirst())
            } else if line.hasPrefix("n") {
                pidToCwd[currentPid] = String(line.dropFirst())
            }
        }

        let sortedTtys = ttyToPids.keys.sorted()
        let prefix = prefixForm(cwd)
        for tty in sortedTtys {
            let cwds = ttyToPids[tty, default: []].compactMap { pidToCwd[$0] }
            if cwds.contains(cwd) { return "/dev/" + tty }
        }
        for tty in sortedTtys {
            let cwds = ttyToPids[tty, default: []].compactMap { pidToCwd[$0] }
            if cwds.contains(where: { $0.hasPrefix(prefix) }) { return "/dev/" + tty }
        }
        return nil
    }

    private static func isRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private static func prefixForm(_ cwd: String) -> String {
        cwd.hasSuffix("/") ? cwd : cwd + "/"
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) -> String? {
        if Thread.isMainThread {
            return executeAppleScript(source)
        }
        return DispatchQueue.main.sync { executeAppleScript(source) }
    }

    private static func executeAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue ?? ""
    }

    private static func runCommand(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
