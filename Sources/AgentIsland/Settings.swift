import AppKit
import ServiceManagement
import SwiftUI

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "soundsEnabled": true,
            "soundVolume": 0.6,
            "finishedCollapseSeconds": 6.0,
            "needsInputCollapseSeconds": 8.0,
            "quietWhenFocused": true,
            "respectFocusModes": true,
            "hideWhenScreenShared": true,
        ])
    }

    var soundsEnabled: Bool {
        get { defaults.bool(forKey: "soundsEnabled") }
        set { defaults.set(newValue, forKey: "soundsEnabled") }
    }

    var soundVolume: Double {
        get { min(max(defaults.double(forKey: "soundVolume"), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: "soundVolume") }
    }

    var finishedCollapseSeconds: Double {
        get { min(max(defaults.double(forKey: "finishedCollapseSeconds"), 2), 30) }
        set { defaults.set(min(max(newValue, 2), 30), forKey: "finishedCollapseSeconds") }
    }

    var needsInputCollapseSeconds: Double {
        get { min(max(defaults.double(forKey: "needsInputCollapseSeconds"), 2), 30) }
        set { defaults.set(min(max(newValue, 2), 30), forKey: "needsInputCollapseSeconds") }
    }

    var quietWhenFocused: Bool {
        get { defaults.bool(forKey: "quietWhenFocused") }
        set { defaults.set(newValue, forKey: "quietWhenFocused") }
    }

    var respectFocusModes: Bool {
        get { defaults.bool(forKey: "respectFocusModes") }
        set { defaults.set(newValue, forKey: "respectFocusModes") }
    }

    var hideWhenScreenShared: Bool {
        get { defaults.bool(forKey: "hideWhenScreenShared") }
        set { defaults.set(newValue, forKey: "hideWhenScreenShared") }
    }
}

struct SettingsView: View {
    @AppStorage("soundsEnabled") private var soundsEnabled = true
    @AppStorage("soundVolume") private var soundVolume = 0.6
    @AppStorage("finishedCollapseSeconds") private var finishedCollapseSeconds = 6.0
    @AppStorage("needsInputCollapseSeconds") private var needsInputCollapseSeconds = 8.0
    @AppStorage("quietWhenFocused") private var quietWhenFocused = true
    @AppStorage("respectFocusModes") private var respectFocusModes = true
    @AppStorage("hideWhenScreenShared") private var hideWhenScreenShared = true
    @State private var claudeStatus = AgentSetup.claudeStatus()
    @State private var codexStatus = AgentSetup.codexStatus()
    @State private var loginItemStatus = SMAppService.mainApp.status

    private var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private var startAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled },
            set: { enable in
                if enable {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
                loginItemStatus = SMAppService.mainApp.status
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("General") {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Start at login", isOn: startAtLogin)
                        .disabled(!isBundledApp)
                    if !isBundledApp {
                        Text("Available when running the installed app.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if loginItemStatus == .requiresApproval {
                        Text("Approve in System Settings → Login Items")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Sounds") {
                Toggle("Play sounds", isOn: $soundsEnabled)
                HStack {
                    Text("Volume")
                    Slider(value: $soundVolume, in: 0...1)
                    Text("\(Int(soundVolume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .disabled(!soundsEnabled)
            }
            Section("Island") {
                Stepper(value: $finishedCollapseSeconds, in: 2...30, step: 1) {
                    HStack {
                        Text("Collapse after finished")
                        Spacer()
                        Text("\(Int(finishedCollapseSeconds))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $needsInputCollapseSeconds, in: 2...30, step: 1) {
                    HStack {
                        Text("Collapse after needs input")
                        Spacer()
                        Text("\(Int(needsInputCollapseSeconds))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Stay quiet when I'm in that terminal", isOn: $quietWhenFocused)
                    Text("Skips the pop and sound when the session's terminal is already frontmost.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Respect macOS Focus", isOn: $respectFocusModes)
                    Text("Mute pops and sounds while a Focus is on.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Toggle("Hide details while screen is shared", isOn: $hideWhenScreenShared)
            }
            Section("Connect agents") {
                agentRow(name: "Claude Code", status: claudeStatus) {
                    if claudeStatus == .connected {
                        _ = try? AgentSetup.disconnectClaude()
                    } else {
                        _ = try? AgentSetup.connectClaude()
                    }
                    claudeStatus = AgentSetup.claudeStatus()
                }
                if codexStatus != .notInstalled {
                    agentRow(name: "Codex", status: codexStatus) {
                        if codexStatus == .connected {
                            _ = try? AgentSetup.disconnectCodex()
                        } else {
                            _ = try? AgentSetup.connectCodex()
                        }
                        codexStatus = AgentSetup.codexStatus()
                    }
                }
                Text("Writes hook entries to ~/.claude/settings.json — existing hooks are preserved. Takes effect in new sessions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Island \(appVersion)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("⌃⌥A approve · ⌃⌥D deny · ⌃⌥I toggle island")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.dark)
    }

    private func agentRow(name: String, status: AgentSetup.Status, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            statusLabel(status)
                .font(.system(size: 11))
            if status != .manualSetupNeeded {
                Button(status == .connected ? "Disconnect" : "Connect", action: action)
            }
        }
    }

    private func statusLabel(_ status: AgentSetup.Status) -> Text {
        switch status {
        case .connected:
            Text("Connected ✓").foregroundStyle(.green)
        case .manualSetupNeeded:
            Text("Manual setup needed").foregroundStyle(.orange)
        default:
            Text("Not connected").foregroundStyle(.secondary)
        }
    }
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func open() {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Agent Island Settings"
            newWindow.level = .floating
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(rootView: SettingsView())
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
