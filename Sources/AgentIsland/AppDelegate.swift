import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

extension NSScreen {
    var notchSize: CGSize {
        let height = safeAreaInsets.top > 0 ? safeAreaInsets.top : 30
        var width: CGFloat = 200
        if safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            width = frame.width - left.width - right.width
        }
        return CGSize(width: width, height: height)
    }
}

final class NotchPanel: NSPanel {
    init(screen: NSScreen, store: SessionStore) {
        let size = NSSize(width: 640, height: 420)
        let rect = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        contentView = NSHostingView(rootView: IslandView(store: store, notchSize: screen.notchSize))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    private var panel: NotchPanel?
    private var server: EventServer?
    private var statusItem: NSStatusItem?
    private var updater: SPUStandardUpdaterController?
    private var hotKeys: HotKeys?

    private var runsAsBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        takeOverPort()
        if runsAsBundle {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        hotKeys = HotKeys(store: store)
        hotKeys?.register()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runOnboardingIfNeeded()
        }
        server = EventServer(store: store)
        server?.start()
        setupPanel()
        setupStatusItem()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupPanel()
        }
    }

    private func runOnboardingIfNeeded() {
        guard runsAsBundle else { return }
        let key = "onboardingDone"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let claude = AgentSetup.claudeStatus()
        let codex = AgentSetup.codexStatus()
        guard claude == .notConnected || codex == .notConnected else { return }
        let agents = codex == .notConnected ? "Claude Code and Codex sessions" : "Claude Code sessions"
        let alert = NSAlert()
        alert.messageText = "Connect your agents?"
        alert.informativeText = "Agent Island adds hook entries so your \(agents) appear on the island — finishes, questions, and permission prompts. Existing settings are preserved and a backup is made first. Agent Island will also start at login. You can change both any time in Settings."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if claude == .notConnected { _ = try? AgentSetup.connectClaude() }
            if codex == .notConnected { _ = try? AgentSetup.connectCodex() }
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func openInspector() {
        EventInspectorWindowController.shared.open()
    }

    private func takeOverPort() {
        guard !EventServer.portFree() else { return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(EventServer.port)/quit")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 1
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 1.5)
        for _ in 0..<10 {
            if EventServer.portFree() { return }
            usleep(300_000)
        }
        NSLog("AgentIsland: port \(EventServer.port) still busy after takeover attempt")
    }

    private func setupPanel() {
        panel?.close()
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let newPanel = NotchPanel(screen: screen, store: store)
        newPanel.orderFrontRegardless()
        panel = newPanel
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AgentIsland")
        let menu = NSMenu()
        let testItem = NSMenuItem(title: "Send Test Event", action: #selector(sendTestEvent), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)
        let inspectorItem = NSMenuItem(title: "Event Inspector…", action: #selector(openInspector), keyEquivalent: "i")
        inspectorItem.target = self
        menu.addItem(inspectorItem)
        if let updater {
            let updateItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            updateItem.target = updater
            menu.addItem(updateItem)
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit AgentIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.open()
    }

    @objc private func sendTestEvent() {
        store.apply(AgentEvent(
            id: "test",
            source: "claude",
            kind: "finished",
            message: "Refactored the auth module — 3 files changed",
            cwd: NSHomeDirectory() + "/personal/agent-island"
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.store.apply(AgentEvent(id: "test", source: "claude", kind: "ended", message: "", cwd: ""))
        }
    }
}
