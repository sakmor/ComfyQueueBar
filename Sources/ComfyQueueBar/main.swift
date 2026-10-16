import AppKit
import Foundation
import SwiftUI
import WebKit
#if !DOCUMENTATION_SCREENSHOT
import Sparkle
#endif

#if !DOCUMENTATION_SCREENSHOT
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    let controller: SPUStandardUpdaterController
    @Published var automaticallyUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyUpdates
            controller.updater.automaticallyDownloadsUpdates = automaticallyUpdates
        }
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyUpdates = controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
    }

    func check() { controller.checkForUpdates(nil) }
}
#endif

#if DOCUMENTATION_SCREENSHOT
@main
struct DocumentationCapture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dark = CommandLine.arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if CommandLine.arguments.contains("--interactive") {
            let delegate = StatusBarController()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--menu-bar") {
            let status = NSStatusBar.system.statusItem(withLength: 84)
            guard let button = status.button else { fatalError("No status button") }
            button.image = QueueBrand.menuBarIcon
            button.imagePosition = .imageLeading
            StatusBarLabelStyle.apply(" 1/2", to: button, warning: false)
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.contentView = NSHostingView(rootView: QueuePopover(queue: QueueViewModel()).frame(width: 420, height: 540).clipShape(RoundedRectangle(cornerRadius: 12)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
            panel.setFrameOrigin(NSPoint(x: anchor.midX - 210, y: anchor.minY - 548))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            app.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            if let argument = CommandLine.arguments.firstIndex(of: "--desktop-output") {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
                let region = "\(Int(panel.frame.minX)),\(Int(NSScreen.screens[0].frame.maxY - anchor.maxY)),420,\(Int(anchor.height) + 548)"
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", region, CommandLine.arguments[argument + 1]]
                try! capture.run(); capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
                panel.close()
                return
            }
            withExtendedLifetime((status, panel)) { app.run() }
            return
        }
        let queue = QueueViewModel()
        let settings = CommandLine.arguments.contains("--settings")
        let preview = CommandLine.arguments.contains("--preview")
        let workspace = CommandLine.arguments.contains("--workspace")
        let narrow = CommandLine.arguments.contains("--narrow")
        let width: CGFloat = preview ? 440 : (workspace ? (narrow ? 780 : 940) : (settings ? 560 : 420))
        let height: CGFloat = preview ? 460 : (workspace ? (narrow ? 540 : 680) : (settings ? 680 : 540))
        let previewModel = MediaPreviewModel()
        let panel = QueuePopoverState()
        if CommandLine.arguments.contains("--history") { panel.section = .history }
        if settings && workspace { panel.section = .settings }
        if CommandLine.arguments.contains("--notifications") { panel.settingsSection = .notifications }
        let interface = QueuePopover(queue: queue, panel: panel, expanded: workspace)
        let root = preview ? AnyView(MediaPreview(job: queue.completed[0], endpoint: queue.endpoint, model: previewModel).frame(width: 440, height: 460).background(.regularMaterial))
            : settings && !workspace ? AnyView(interface.settingsContent.background(.regularMaterial)) : AnyView(interface)
        let view = NSHostingView(rootView: root.frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot capture view") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        window.close()
    }
}
#else
@main
struct ComfyQueueBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = StatusBarController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

#endif
