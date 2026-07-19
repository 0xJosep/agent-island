import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AgentIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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
