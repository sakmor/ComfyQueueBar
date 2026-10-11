import AppKit
import Combine
import SwiftUI

/// Own the status item independently of SwiftUI scene visibility.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let queue = QueueViewModel()
    private let panelState = QueuePopoverState()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var fallback: NSWindow?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DOCUMENTATION_SCREENSHOT
        _ = AppUpdater.shared
        #endif
        installEditingMenu()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 540)
        popover.contentViewController = NSHostingController(rootView:
            QueuePopover(queue: queue, panel: panelState, onOpenWorkspace: { [weak self] settings in
                self?.showFallback(settings: settings)
            }).frame(width: 420, height: 540))
        restoreItem()
        subscription = queue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restoreItem() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restoreItem() }
        })
    }

    private func installEditingMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ComfyQueueBar")
        appMenu.addItem(withTitle: L10n.text("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.text("Edit"))
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: L10n.text(title), action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.text("Window"))
        windowMenu.addItem(withTitle: L10n.text("Close window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.text("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    private func restoreItem() {
        if item == nil {
            let status = NSStatusBar.system.statusItem(withLength: 52)
            // Keep this utility's sole entry point from being removed via Command-drag.
            status.behavior = []
            status.button?.target = self
            status.button?.action = #selector(togglePanel)
            status.button?.image = QueueBrand.menuBarIcon
            status.button?.imagePosition = .imageLeading
            item = status
        }
        item?.isVisible = true
        updateLabel()
    }

    private func updateLabel() {
        let multiple = queue.monitoredServers.count > 1
        item?.length = multiple ? 84 : 52
        item?.button?.title = " " + (multiple ? queue.fleetBadge : queue.queueBadge)
        item?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let status = queue.hasFreshQueue ? L10n.text("ComfyUI queue: %@ jobs", String(queue.totalJobs)) : queue.monitoringState.label
        if multiple {
            let summary = L10n.text("%@ available / %@ servers", String(queue.availableServerCount), String(queue.monitoredServers.count))
            let details = queue.monitoredServers.map { server in
                let counts = server.state == .connected
                    ? " · " + L10n.text("%@ running · %@ waiting", String(server.runningCount), String(server.pendingCount)) : ""
                return server.name + " · " + server.statusLabel + counts
            }
            item?.button?.toolTip = ([summary] + details).joined(separator: "\n")
        } else {
            item?.button?.toolTip = queue.serverName + " · " + ConnectionAddress.portLabel(queue.endpoint) + " · " + status
        }
        item?.button?.setAccessibilityLabel(item?.button?.toolTip)
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item?.button else { showFallback(); return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreItem()
        // macOS controls status-item placement. A normal window stays usable even
        // when menu bar space is exhausted or the camera housing obscures an item.
        showFallback()
        return false
    }

    private func showFallback(settings: Bool = false) {
        popover.performClose(nil)
        if settings { panelState.section = .settings }
        if fallback == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "ComfyQueueBar"
            window.contentMinSize = NSSize(width: 780, height: 540)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: QueuePopover(queue: queue, panel: panelState, expanded: true))
            window.center()
            fallback = window
        }
        NSApp.activate(ignoringOtherApps: true)
        fallback?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
}
