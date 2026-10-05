#if !DOCUMENTATION_SCREENSHOT
import AppKit
import Combine
import SwiftUI

/// Own the status item independently of SwiftUI scene visibility.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let queue = QueueViewModel()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var fallback: NSWindow?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppUpdater.shared
        installEditingMenu()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 600)
        popover.contentViewController = NSHostingController(rootView: QueuePopover(queue: queue).frame(width: 360, height: 600))
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
        // Bound width even for large queues; the full count is available in the tooltip.
        item?.button?.title = " " + queue.queueBadge
        item?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let status = queue.hasFreshQueue ? L10n.text("ComfyUI queue: %@ jobs", String(queue.totalJobs)) : queue.monitoringState.label
        item?.button?.toolTip = queue.serverName + " · " + ConnectionAddress.portLabel(queue.endpoint) + " · " + status
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

    private func showFallback() {
        popover.performClose(nil)
        if fallback == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "ComfyQueueBar"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: QueuePopover(queue: queue).frame(width: 360, height: 600))
            window.center()
            fallback = window
        }
        NSApp.activate(ignoringOtherApps: true)
        fallback?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
}
#endif
