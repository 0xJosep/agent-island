import AppKit
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
}

struct SettingsView: View {
    @AppStorage("soundsEnabled") private var soundsEnabled = true
    @AppStorage("soundVolume") private var soundVolume = 0.6
    @AppStorage("finishedCollapseSeconds") private var finishedCollapseSeconds = 6.0
    @AppStorage("needsInputCollapseSeconds") private var needsInputCollapseSeconds = 8.0
    @AppStorage("quietWhenFocused") private var quietWhenFocused = true

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
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
