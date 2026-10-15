import AppKit
import Foundation
import SwiftUI
import WebKit

enum QueueBrand {
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // Three queue rows with a separate play marker, readable at menu-bar size.
            for y in [3.0, 8.0, 13.0] {
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: 10, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 13, y: 5))
            play.line(to: NSPoint(x: 13, y: 13))
            play.line(to: NSPoint(x: 18, y: 9))
            play.close()
            play.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static var panelIcon: Image {
        if let url = Bundle.main.url(forResource: "AppIconPreview", withExtension: "png"), let icon = NSImage(contentsOf: url) {
            return Image(nsImage: icon)
        }
        return Image(systemName: "square.stack.3d.up.fill")
    }
}

enum WorkspaceSection: String, CaseIterable {
    case queue, history, settings
    var label: String {
        switch self { case .queue: return L10n.text("Queue"); case .history: return L10n.text("History"); case .settings: return L10n.text("Settings") }
    }
}

enum SettingsSection: String, CaseIterable {
    case servers, notifications, agents, app
    var label: String {
        switch self { case .servers: return L10n.text("Connections"); case .notifications: return L10n.text("Notifications"); case .agents: return L10n.text("Agents"); case .app: return L10n.text("App") }
    }
}

@MainActor
final class QueuePopoverState: ObservableObject {
    @Published var urlInput = ""
    @Published var confirmation: QueueConfirmation?
    @Published var section: WorkspaceSection = .queue
    @Published var settingsSection: SettingsSection = .servers
    @Published var serverSearch = ""
    @Published var availableOnly = false
    @Published var profileName = ""
    @Published var historyRange: HistoryRange = .day
    @Published var historySearch = ""
    @Published var showsFailures = false
}

struct QueuePopover: View {
    @ObservedObject var queue: QueueViewModel
    @StateObject private var panel: QueuePopoverState
    var expanded: Bool
    var onOpenWorkspace: ((Bool) -> Void)?

    init(queue: QueueViewModel, panel: QueuePopoverState? = nil, expanded: Bool = false, onOpenWorkspace: ((Bool) -> Void)? = nil) {
        self.queue = queue
        _panel = StateObject(wrappedValue: panel ?? QueuePopoverState())
        self.expanded = expanded
        self.onOpenWorkspace = onOpenWorkspace
    }
    #if !DOCUMENTATION_SCREENSHOT
    @ObservedObject private var updater = AppUpdater.shared
    #endif

    var body: some View {
        Group {
            if expanded { workspace }
            else { compactOverview }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if panel.urlInput.isEmpty { panel.urlInput = queue.endpoint } }
        .onChange(of: queue.endpoint) { panel.urlInput = $0 }
        .confirmationDialog(panel.confirmation?.title ?? L10n.text("Confirm action"), isPresented: Binding(
            get: { panel.confirmation.map { _ in true } ?? false },
            set: { if !$0 { panel.confirmation = nil } }
        ), titleVisibility: .visible) {
            if let confirmation = panel.confirmation {
                switch confirmation {
                case .prioritize(let job):
                    Button(L10n.text("Prioritize and resubmit")) {
                        panel.confirmation = nil
                        Task { await queue.moveToFront(job) }
                    }
                case .removeServer(let profile):
                    Button(L10n.text("Remove server"), role: .destructive) {
                        panel.confirmation = nil
                        queue.deleteProfile(profile.id)
                    }
                case .stop(let job):
                    Button(L10n.text("Stop running job"), role: .destructive) {
                        panel.confirmation = nil
                        Task { await queue.stopRunning(job) }
                    }
                }
            }
            Button(L10n.text("Cancel"), role: .cancel) { panel.confirmation = nil }
        } message: {
            Text(panel.confirmation?.message ?? "")
        }
    }

    private var renderingServerCount: Int {
        queue.monitoredServers.filter { $0.state == .connected && $0.runningCount > 0 }.count
    }

    private var waitingServerCount: Int {
        queue.monitoredServers.filter { $0.state == .connected && $0.runningCount == 0 && $0.pendingCount > 0 }.count
    }

    private var visibleServers: [MonitoredServer] {
        queue.monitoredServers.filter {
            (!panel.availableOnly || $0.isAvailable) &&
            (panel.serverSearch.isEmpty || ($0.name + " " + $0.endpoint).localizedCaseInsensitiveContains(panel.serverSearch))
        }
    }

    private var compactOverview: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                summaryMetric(queue.availableServerCount, "Ready hosts", color: .green)
                summaryMetric(renderingServerCount, "Rendering hosts", color: .blue)
                summaryMetric(waitingServerCount, "Waiting servers", color: .orange)
                summaryMetric(queue.serversWithoutFreshStatusCount, "Unknown hosts", color: .red)
            }.padding(.horizontal, 18).padding(.bottom, 18)
            Divider()
            serverBrowser
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            QueueBrand.panelIcon.resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("ComfyQueueBar").font(.system(size: 14, weight: .semibold))
                Text(L10n.text("Render overview")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { queue.refreshServers(force: true) } label: {
                Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help(L10n.text("Refresh now")).accessibilityLabel(L10n.text("Refresh now"))
        }.padding(18)
    }

    private func summaryMetric(_ count: Int, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(count)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(L10n.text(label)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                QueueBrand.panelIcon.resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
                Text(L10n.text("Render workspace")).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                summaryMetric(queue.availableServerCount, "Ready hosts", color: .green)
                summaryMetric(renderingServerCount, "Rendering hosts", color: .blue)
                summaryMetric(waitingServerCount, "Waiting servers", color: .orange)
                summaryMetric(queue.serversWithoutFreshStatusCount, "Unknown hosts", color: .red)
            }.padding(.horizontal, 22).padding(.vertical, 16)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    serverBrowser
                    Button { panel.settingsSection = .servers; panel.section = .settings } label: {
                        Label(L10n.text("Manage servers"), systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).font(.system(size: 12)).padding(16)
                }
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 310)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
                workspaceDetail.frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 780, minHeight: 540)
    }

    private var workspaceDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if panel.section == .settings {
                HStack {
                    Text(L10n.text("Settings")).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button(L10n.text("Back to queue")) { panel.section = .queue }.controlSize(.small)
                }.padding(24)
                Divider()
                ScrollView { settingsContent }
            } else if !queue.hasSelectedServer {
                VStack(spacing: 14) {
                    Image(systemName: "desktopcomputer").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(L10n.text("No monitored servers")).font(.system(size: 18, weight: .semibold))
                    Text(L10n.text("Add a server to start monitoring its queue.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(L10n.text("Add a server")) { panel.settingsSection = .servers; panel.section = .settings }
                        .buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                selectedServerHeader
                HStack {
                    Picker(L10n.text("View"), selection: $panel.section) {
                        Text(L10n.text("Queue")).tag(WorkspaceSection.queue)
                        Text(historyTabTitle).tag(WorkspaceSection.history)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    Spacer()
                    Button { panel.section = .settings } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).help(L10n.text("Settings")).accessibilityLabel(L10n.text("Settings"))
                }.padding(.horizontal, 24).padding(.bottom, 18)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        actionFeedback
                        if panel.section == .history { completedSection; failureSection }
                        else { runningSection; pendingSection }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Circle().fill(queue.hasFreshQueue ? Color.green : Color.orange).frame(width: 5, height: 5)
                    Text(queue.monitoringState.label)
                    Spacer()
                    Text(queue.lastUpdated.map { L10n.text("Updated %@", $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))) } ?? L10n.text("Refreshes every 4 seconds"))
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
    }

    private var selectedServerHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(queue.serverName).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Text(queue.endpoint).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Button { queue.reviewConnection(to: queue.endpoint) } label: { Label(L10n.text("Connection"), systemImage: "network") }
                .buttonStyle(.bordered).help(L10n.text("Review this connection")).accessibilityLabel(L10n.text("Review this connection"))
                .disabled(!queue.canChangeServer)
            Button { Task { await queue.refresh(forceHistory: true) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered).help(L10n.text("Refresh now")).accessibilityLabel(L10n.text("Refresh now"))
                .disabled(queue.isLoading || !queue.canChangeServer)
        }.padding(24)
    }

    private var serverBrowser: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n.text("Find a server"), text: $panel.serverSearch).textFieldStyle(.plain)
                    if !panel.serverSearch.isEmpty {
                        Button { panel.serverSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(L10n.text("Clear search"))
                    }
                }.font(.system(size: 12)).padding(9)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                Picker(L10n.text("Servers"), selection: $panel.availableOnly) {
                    Text(L10n.text("All servers")).tag(false)
                    Text(L10n.text("Available")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
            }.padding(14)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visibleServers) { server in serverRow(server) }
                    if visibleServers.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 23))
                            Text(L10n.text(queue.monitoredServers.isEmpty ? "No monitored servers" : panel.availableOnly ? "No servers available" : "No matching servers"))
                                .font(.system(size: 12))
                            if queue.monitoredServers.isEmpty {
                                Button(L10n.text("Add a server")) {
                                    panel.settingsSection = .servers; panel.section = .settings
                                    if !expanded { onOpenWorkspace?(true) }
                                }.buttonStyle(.link).font(.system(size: 11))
                            } else {
                                Button(L10n.text("Show all servers")) { panel.serverSearch = ""; panel.availableOnly = false }
                                    .buttonStyle(.link).font(.system(size: 11))
                            }
                        }.foregroundStyle(.secondary).padding(.vertical, 30).frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
    }

    private func serverRow(_ server: MonitoredServer) -> some View {
        let selected = MultiServerMonitor.key(queue.endpoint) == server.endpoint
        return Button {
            panel.profileName = server.name
            panel.section = .queue
            if !selected { Task { await queue.connect(to: server.endpoint) } }
            if !expanded { onOpenWorkspace?(false) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: server.endpoint.contains(".gputw.ai") ? "cloud" : "desktopcomputer")
                    .font(.system(size: 16)).foregroundStyle(serverColor(server)).frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(server.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(server.statusLabel).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            .foregroundStyle(serverColor(server)).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(serverColor(server).opacity(0.09), in: Capsule())
                    }
                    HStack(spacing: 3) {
                        if server.isAvailable {
                            if let date = server.becameAvailableAt {
                                Text(L10n.text("Queue empty since")); Text(date, style: .time)
                            } else { Text(L10n.text("Ready for next batch")) }
                        } else if server.state == .connected {
                            Text(L10n.text("%@ running · %@ waiting", String(server.runningCount), String(server.pendingCount)))
                        } else { Text(L10n.text("Availability unknown")) }
                    }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 10).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected && expanded ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).disabled(!queue.canChangeServer || queue.isClearingGPUTW)
        .accessibilityHint(L10n.text("Select to view details. All servers keep monitoring."))
        .help([server.endpoint, L10n.text("Select to view details. All servers keep monitoring."), server.error ?? server.currentJobTitle ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    #if !DOCUMENTATION_SCREENSHOT
    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("Automatically update the app"), isOn: $updater.automaticallyUpdates)
            .toggleStyle(.checkbox)
            Button(L10n.text("Check for updates…")) { AppUpdater.shared.check() }
                .controlSize(.small)
        }
        .font(.system(size: 11))
    }
    #endif

    private var serverSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.text("Saved addresses")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(L10n.text("All saved servers are monitored continuously. Select a server to view its queue."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(queue.profiles) { profile in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Button {
                            panel.urlInput = profile.endpoint
                            panel.profileName = profile.name
                            queue.reviewConnection(to: profile.endpoint)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name).fontWeight(.medium)
                                Text(profile.endpoint).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    .lineLimit(2).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(!queue.canChangeServer)
                        if profile.endpoint == queue.endpoint { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { panel.confirmation = .removeServer(profile) } label: {
                            Label(L10n.text("Remove server"), systemImage: "minus.circle")
                        }.buttonStyle(.borderless).foregroundStyle(.red).controlSize(.small)
                            .disabled(!queue.canChangeServer || queue.isClearingGPUTW)
                    }
                    WakeSettingsView(queue: queue, profile: profile)
                }
            }
        }.font(.system(size: 11))
    }

    private var progressExtensionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Node progress")).font(.subheadline).fontWeight(.medium)
            Button(L10n.text("Install progress extension…")) {
                let panel = NSOpenPanel()
                panel.title = L10n.text("Choose the ComfyUI folder")
                panel.message = L10n.text("Installs on this Mac only. For a remote ComfyUI server, install the extension on that server.")
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let folder = panel.url else { return }
                let didAccess = folder.startAccessingSecurityScopedResource()
                defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
                queue.installProgressExtension(in: folder)
            }
            .controlSize(.small)
            Text(L10n.text("Installs on this Mac only. For a remote ComfyUI server, install the extension on that server."))
                .font(.caption).foregroundStyle(.secondary)
            if let message = queue.progressExtensionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = queue.progressExtensionError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .font(.system(size: 11))
    }
    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L10n.text("Notify when any server becomes available"), isOn: $queue.notifyAvailability).toggleStyle(.checkbox)
                .onChange(of: queue.notifyAvailability) { enabled in if enabled { Task { await queue.authorizeNotifications() } } }
            Picker(L10n.text("Completion notifications"), selection: $queue.notificationMode) {
                Text(L10n.text("Off")).tag("off")
                Text(L10n.text("Every job")).tag("each")
                Text(L10n.text("Whole batch")).tag("batch")
            }.controlSize(.small)
            .onChange(of: queue.notificationMode) { mode in
                if mode != "off" { Task { await queue.authorizeNotifications() } }
            }
            Toggle(L10n.text("Notify failures and disconnections"), isOn: $queue.notifyProblems).toggleStyle(.checkbox)
                .onChange(of: queue.notifyProblems) { enabled in if enabled { Task { await queue.authorizeNotifications() } } }
            if let message = queue.permissionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.font(.system(size: 11))
    }

    private func serverColor(_ server: MonitoredServer) -> Color {
        if server.isAvailable { return .green }
        if server.state == .connected && server.runningCount > 0 { return .blue }
        return .orange
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("ComfyUI address"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8188", text: $panel.urlInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { queue.reviewConnection(to: panel.urlInput) }
                Button(L10n.text("Connect")) {
                    queue.reviewConnection(to: panel.urlInput)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!queue.canChangeServer)
            }
            HStack(spacing: 8) {
                TextField(L10n.text("Server name"), text: $panel.profileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button(L10n.text("Save address")) {
                    if queue.saveProfile(name: panel.profileName, address: panel.urlInput) {
                        panel.profileName = ""
                    }
                }.controlSize(.small)
            }
            HStack {
                Button(L10n.text("Sign in to GPUtw…")) { queue.signInToGPUTW(address: panel.urlInput) }
                Button(L10n.text("Clear GPUtw sign-in")) { Task { await queue.clearGPUTWLogin() } }
            }.controlSize(.small).disabled(!queue.canChangeServer || queue.isClearingGPUTW)
            Text(L10n.text("For private or password-protected GPUtw ComfyUI instances."))
                .font(.caption).foregroundStyle(.secondary)
            if let message = queue.connectionMessage {
                Text(message).font(.caption)
                    .foregroundStyle(queue.connectionMessageIsError ? Color.red : Color.secondary)
            }
            LANDiscoveryView(queue: queue) { server in
                panel.urlInput = server.endpoint
                panel.profileName = server.name
                queue.reviewConnection(to: server.endpoint)
            }.padding(.top, 6)
            if !queue.profiles.isEmpty { serverSettings.padding(.top, 6) }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Running"), count: queue.hasFreshQueue ? queue.running.count : nil, symbol: "waveform.path")
            if !queue.hasFreshQueue {
                connectionError
            } else if queue.running.isEmpty {
                emptyState(L10n.text("No jobs are running"), symbol: "checkmark.circle")
                if queue.pending.isEmpty {
                    if let pairedEndpoint = queue.pairedPortEndpoint {
                        pairedPortStatus(endpoint: pairedEndpoint)
                    } else {
                        Text(L10n.text("Expecting a running job? Check the server port.")).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            } else {
                VStack(spacing: 0) {
                ForEach(queue.running) { job in
                    JobCard(
                        job: job,
                        state: .running,
                        progress: queue.queueProgress,
                        progressBridgeStatus: queue.progressBridgeStatus,
                        isMoving: false,
                        isStopping: queue.stoppingJobID == job.id,
                        isActionEnabled: queue.movingJobID == nil && queue.stoppingJobID == nil && !queue.isLoading,
                        onPrioritize: nil,
                        onStop: { panel.confirmation = .stop(job) },
                        timing: { now in queue.timingText(for: job, now: now) }
                    )
                    if job.id != queue.running.last?.id { Divider().padding(.leading, 14) }
                }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }

    @ViewBuilder
    private func pairedPortStatus(endpoint: String) -> some View {
        let port = ConnectionAddress.port(endpoint)
        VStack(alignment: .leading, spacing: 6) {
            switch queue.pairedQueueStatus {
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Checking paired GPUtw port %@…", port))
                }.font(.caption).foregroundStyle(.secondary)
            case .empty:
                Text(L10n.text("Paired port %@ is also empty.", port))
                    .font(.caption).foregroundStyle(.secondary)
            case .work(let running, let waiting, let title):
                Label(L10n.text("Found work on paired port %@.", port), systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(L10n.text("Running %@ · Waiting %@", String(running), String(waiting)))
                    .font(.caption).foregroundStyle(.secondary)
                if let title {
                    Text(title).font(.caption).lineLimit(2).help(title)
                }
            case .issue(.portNotEnabled):
                Text(L10n.text("GPUtw port %@ returned 404. Enable it as an HTTP port in Network Ports; private ports need one dashboard handoff from Other ports.", port))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Open GPUtw dashboard")) {
                    queue.signInToGPUTW(address: GPUTWAddress.dashboard.absoluteString)
                }.buttonStyle(.link).font(.caption)
            case .issue(.signInRequired):
                Text(L10n.text("GPUtw port %@ needs an owner session. Open it from the dashboard's Other ports menu.", port))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Open GPUtw dashboard")) {
                    queue.signInToGPUTW(address: GPUTWAddress.dashboard.absoluteString)
                }.buttonStyle(.link).font(.caption)
            case .issue(.unavailable):
                Text(L10n.text("Could not check paired GPUtw port %@. Check your connection and retry.", port))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Retry paired port check"), action: queue.retryPairedPortCheck)
                    .buttonStyle(.link).font(.caption)
            case nil:
                Text(L10n.text("Expecting a running job? Check the server port."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                    .buttonStyle(.link).font(.caption)
            }
            if case .work = queue.pairedQueueStatus {
                Button(L10n.text("Review Port %@", port)) { queue.reviewConnection(to: endpoint) }
                    .buttonStyle(.link).font(.caption)
            } else if case .empty = queue.pairedQueueStatus {
                Button(L10n.text("Review this connection")) { queue.reviewConnection(to: queue.endpoint) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Waiting queue"), count: queue.hasFreshQueue ? queue.pending.count : nil, symbol: "list.number")
            if queue.hasFreshQueue && queue.pending.isEmpty {
                emptyState(L10n.text("No waiting jobs"), symbol: "tray")
            } else if queue.hasFreshQueue {
                VStack(spacing: 0) {
                ForEach(queue.pending) { job in
                    JobCard(
                        job: job,
                        state: .pending,
                        progress: nil,
                        progressBridgeStatus: .checking,
                        isMoving: queue.movingJobID == job.id,
                        isStopping: false,
                        isActionEnabled: queue.movingJobID == nil && queue.stoppingJobID == nil && !queue.isLoading,
                        onPrioritize: { panel.confirmation = .prioritize(job) },
                        onStop: nil
                    )
                    if job.id != queue.pending.last?.id { Divider().padding(.leading, 14) }
                }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }

    private var filteredCompleted: [CompletedJob] {
        queue.completed.filter { job in
            panel.historyRange.includes(job.finishedAt) && (panel.historySearch.isEmpty || ([job.title] + job.filenames).joined(separator: " ").localizedCaseInsensitiveContains(panel.historySearch))
        }
    }
    private var filteredFailures: [FailedJob] {
        queue.failures.filter { job in
            panel.historyRange.includes(job.date) && (panel.historySearch.isEmpty || (job.title + " " + job.reason).localizedCaseInsensitiveContains(panel.historySearch))
        }
    }
    private var historyTabTitle: String {
        filteredFailures.isEmpty ? L10n.text("History") : L10n.text("History · %@ issues", String(filteredFailures.count))
    }
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading(L10n.text("Recently completed"), count: filteredCompleted.count, symbol: "checkmark")
            HStack {
                Picker(L10n.text("Time range"), selection: $panel.historyRange) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in Text(L10n.text(range.label)).tag(range) }
                }.labelsHidden().controlSize(.small).frame(width: 140)
                TextField(L10n.text("Search history"), text: $panel.historySearch).textFieldStyle(.roundedBorder).font(.system(size: 11))
            }
            Text(L10n.text("Newest 200 server records"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            if queue.historyUnavailable {
                Text(L10n.text("History unavailable. Showing the last successful refresh.")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if filteredCompleted.isEmpty && !queue.historyUnavailable {
                emptyState(L10n.text("No recently completed jobs"), symbol: "checkmark.circle")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCompleted) { job in
                        CompletionRow(job: job, endpoint: queue.endpoint)
                        if job.id != filteredCompleted.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
            }
        }
    }
    private var failureSection: some View {
        DisclosureGroup(isExpanded: $panel.showsFailures) {
            if filteredFailures.isEmpty {
                Text(L10n.text("No failures in this range")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(filteredFailures) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(L10n.text(job.interrupted ? "Interrupted" : "Failed")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = job.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text(job.reason.isEmpty ? L10n.text("No error details reported") : job.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(String(job.id.prefix(8))).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }.padding(.vertical, 8)
                Divider()
            }
        } label: {
            Text(L10n.text("Failures & interruptions") + " · " + String(filteredFailures.count)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let message = queue.actionMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(queue.actionIsError ? Color.red : Color.green)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((queue.actionIsError ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        } else if queue.movingJobID != nil || queue.stoppingJobID != nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(queue.movingJobID != nil ? L10n.text("Moving job to the front…") : L10n.text("Stopping job…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var connectionError: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(queue.monitoringState.label)
                .font(.system(size: 12, weight: .semibold))
            Text(queue.monitoringState == .stale ? L10n.text("No fresh queue response for 30 seconds. The job count is unknown.")
                 : queue.monitoringState == .checking ? L10n.text("Waiting for the first queue response.")
                 : queue.errorMessage ?? L10n.text("Check that ComfyUI is running and the address is correct."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if queue.monitoringState == .signInRequired, let url = URL(string: queue.endpoint), GPUTWAddress.serviceOrigin(url) != nil {
                Button(L10n.text("Sign in to GPUtw…")) { queue.signInToGPUTW(address: queue.endpoint) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var agentSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("AI agent integration"), isOn: $queue.agentIntegrationEnabled)
            Text(L10n.text("Let agents delegate monitoring to this app using the local MCP bridge."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Shares queue IDs, output references, and errors with local agents."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("App notifications alert you only. AI can wait for events while an MCP request is active; an idle chat cannot be woken by this app."))
                .font(.caption).foregroundStyle(.secondary)
            if let script = Bundle.main.url(forResource: "server", withExtension: "py", subdirectory: "AgentBridge") {
                Button(L10n.text("Set up Claude and Codex")) { Task { await queue.setupAgents() } }
                    .disabled(queue.isSettingUpAgents)
                Text(L10n.text("Registers MCP and installs the shared skill for Claude Code and Codex. Replaced files are backed up; reopen agent sessions afterward."))
                    .font(.caption).foregroundStyle(.secondary)
                if queue.isSettingUpAgents { ProgressView().controlSize(.small) }
                HStack {
                    Button(L10n.text("Copy MCP configuration")) {
                        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
                            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/absolute/path/to/python3"
                        let configuration = ["mcpServers": ["comfyqueuebar": ["command": python, "args": [script.path]] as [String: Any]]]
                        if let data = try? JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys]),
                           let text = String(data: data, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    if let guide = Bundle.main.url(forResource: "README", withExtension: "md", subdirectory: "AgentBridge") {
                        Button(L10n.text("Setup guide")) { NSWorkspace.shared.open(guide) }
                    }
                }
            }
            if let message = queue.agentSetupMessage { Text(message).font(.caption).textSelection(.enabled) }
            if let error = queue.agentBridgeError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker(L10n.text("Settings"), selection: $panel.settingsSection) {
                ForEach(SettingsSection.allCases, id: \.self) { section in Text(section.label).tag(section) }
            }.pickerStyle(.segmented).labelsHidden()
            switch panel.settingsSection {
            case .servers:
                connectionSettings
                Divider()
                progressExtensionSettings
            case .notifications:
                Text(L10n.text("Know when a server is ready for your next batch."))
                    .font(.system(size: 14, weight: .medium))
                notificationSettings
            case .agents:
                agentSettings
            case .app:
                HStack(spacing: 14) {
                    QueueBrand.panelIcon.resizable().scaledToFit().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ComfyQueueBar").font(.headline)
                        Text(L10n.text("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                #if !DOCUMENTATION_SCREENSHOT
                updateSettings
                #endif
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button { onOpenWorkspace?(false) } label: {
                    Label(L10n.text("Open workspace"), systemImage: "rectangle.split.2x1")
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain)
                Spacer()
                Button { onOpenWorkspace?(true) } label: { Image(systemName: "gearshape").frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help(L10n.text("Settings")).accessibilityLabel(L10n.text("Settings"))
                Menu {
                    Text(L10n.text("Refreshes every 4 seconds"))
                    Divider()
                    Button(L10n.text("Quit")) { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                    .menuStyle(.borderlessButton).fixedSize().help(L10n.text("More options"))
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
    }

    private func sectionHeading(_ title: String, count: Int?, symbol: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(count.map(String.init) ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}
