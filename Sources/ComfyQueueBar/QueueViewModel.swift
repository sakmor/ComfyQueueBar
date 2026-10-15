import AppKit
import Foundation
import SwiftUI
import WebKit

enum PairedQueueStatus: Equatable {
    case checking
    case empty
    case work(running: Int, waiting: Int, title: String?)
    case issue(PairedPortIssue)
}

@MainActor
final class QueueViewModel: ObservableObject {
    static let connectionRetryInterval: TimeInterval = 4

    @Published var endpoint: String
    @Published private(set) var running: [QueueJob] = []
    @Published private(set) var pending: [QueueJob] = []
    @Published private(set) var pairedPortEndpoint: String?
    @Published private(set) var pairedQueueStatus: PairedQueueStatus?
    @Published private(set) var isConnected = false
    @Published private(set) var isLoading = false
    @Published private(set) var monitoringState: MonitoringState = .checking
    private var needsSignIn = false
    @Published private(set) var movingJobID: String?
    @Published private(set) var stoppingJobID: String?
    @Published private(set) var queueProgress: QueueProgress?
    @Published private(set) var progressBridgeStatus: ProgressBridgeStatus = .checking
    @Published private(set) var errorMessage: String?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var connectionMessageIsError = false
    @Published private(set) var actionMessage: String?
    @Published private(set) var actionIsError = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var completed: [CompletedJob] = []
    @Published private(set) var historyUnavailable = false
    @Published private(set) var failures: [FailedJob] = []
    @Published private(set) var wakeMessages: [UUID: String] = [:]
    private var lastWakeAttempts: [UUID: Date] = [:]
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var monitoredServers: [MonitoredServer] = []
    private let serverMonitor: MultiServerMonitor
    @Published var notifyAvailability = false {
        didSet { UserDefaults.standard.set(notifyAvailability, forKey: "notifyAvailability") }
    }
    @Published private(set) var isClearingGPUTW = false
    @Published private(set) var observedStarts: [String: Date] = [:]
    @Published private(set) var permissionMessage: String?
    @Published private(set) var progressExtensionMessage: String?
    @Published private(set) var progressExtensionError: String?
    @Published var notificationMode = "off" {
        didSet { UserDefaults.standard.set(notificationMode, forKey: "notificationMode") }
    }
    @Published var notifyProblems = false {
        didSet { UserDefaults.standard.set(notifyProblems, forKey: "notifyProblems") }
    }
    @Published var agentIntegrationEnabled = false {
        didSet {
            UserDefaults.standard.set(agentIntegrationEnabled, forKey: "agentIntegrationEnabled")
            configureAgentBridge()
        }
    }
    @Published private(set) var agentBridgeError: String?
    @Published private(set) var agentSetupMessage: String?
    @Published private(set) var isSettingUpAgents = false
    private var agentBridge: AgentBridge?
    private var agentTimer: Timer?
    private var notificationTracker = NotificationTracker()
    private var connectionGeneration = UUID()
    private var lastHistoryPoll: Date?
    private var lastPairedPortCheck: Date?
    private var pairedPortCheckTask: Task<Void, Never>?
    private var pairedPortCheckToken = UUID()

    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var isProgressLoading = false
    private var secondaryRefreshTask: Task<Void, Never>?
    private var secondaryRefreshForceHistory = false
    private var secondaryRefreshToken = UUID()

    var totalJobs: Int { running.count + pending.count }
    var hasSelectedServer: Bool { !endpoint.isEmpty }
    var hasFreshQueue: Bool { monitoringState == .connected }
    var queueBadge: String { L10n.text("Queue %@", monitoringState.badge(count: totalJobs)) }
    var availableServerCount: Int { monitoredServers.filter(\.isAvailable).count }
    var freshMonitoredServers: [MonitoredServer] { monitoredServers.filter { $0.state == .connected } }
    var serversWithoutFreshStatusCount: Int { monitoredServers.count - freshMonitoredServers.count }
    var fleetRunningCount: Int { freshMonitoredServers.reduce(0) { $0 + $1.runningCount } }
    var fleetWaitingCount: Int { freshMonitoredServers.reduce(0) { $0 + $1.pendingCount } }
    var fleetBadge: String {
        if freshMonitoredServers.isEmpty && serversWithoutFreshStatusCount > 0 {
            return L10n.text("%@ servers unavailable", String(serversWithoutFreshStatusCount))
        }
        return L10n.text("Running %@ · Waiting %@", String(fleetRunningCount), String(fleetWaitingCount))
    }

    private func configureServerMonitor() {
        serverMonitor.configure(profiles: profiles)
    }

    /// Background servers follow the fleet poll policy; the selected server is
    /// refreshed only by `refresh()`, which reports into the fleet monitor.
    func refreshServers(force: Bool = false) {
        #if !DOCUMENTATION_SCREENSHOT
        configureServerMonitor()
        serverMonitor.focus(hasSelectedServer ? endpoint : nil)
        serverMonitor.refresh(force: force)
        #endif
    }

    private func updateMonitoringState() {
        let state = MonitoringState.resolve(connected: isConnected, loading: isLoading, needsSignIn: needsSignIn,
            lastUpdated: lastUpdated, hasError: errorMessage != nil, now: Date())
        if monitoringState != state { monitoringState = state }
    }

    init(serverMonitor suppliedMonitor: MultiServerMonitor? = nil) {
        self.serverMonitor = suppliedMonitor ?? MultiServerMonitor()
        #if DOCUMENTATION_SCREENSHOT
        endpoint = "http://127.0.0.1:8188"
        let graph: [String: Any] = ["12": ["_meta": ["title": "KSampler"], "class_type": "KSampler"]]
        running = [QueueJob(id: "8f21a7c4-demo-running", title: "Ceramic lamp · turntable", nodeCount: 24, queueNumber: 1, position: 1, prompt: graph, extraData: [:])]
        pending = [QueueJob(id: "b390e612-demo-waiting", title: "Ceramic lamp · warm lighting", nodeCount: 18, queueNumber: 2, position: 1, prompt: [:], extraData: [:])]
        isConnected = true
        monitoringState = .connected
        progressBridgeStatus = .available
        queueProgress = QueueProgress(promptID: running[0].id, nodeID: "12", value: 21, maxValue: 30, percent: 70, state: "running")
        let demoNow = Calendar(identifier: .gregorian).startOfDay(for: Date()).addingTimeInterval(14 * 3600 + 32 * 60)
        lastUpdated = demoNow
        let fingerprint = HistoryDetails.fingerprint(graph)
        completed = (0..<3).map { index in
            let end = demoNow.addingTimeInterval(-Double(180 + index * 360))
            let output = MediaOutput(filename: "ceramic_lamp_studio_000\(42 - index).png", subfolder: "product", type: "output")
            return CompletedJob(id: "demo-completed-\(index)", title: index == 0 ? "Ceramic lamp · studio still" : "Ceramic lamp · lighting test \(3 - index)", finishedAt: end, filenames: [output.displayPath], queueNumber: Double(index), outputs: [output], startedAt: end.addingTimeInterval(-240), fingerprint: fingerprint)
        }
        profiles = [ServerProfile(name: "Studio Mac", endpoint: endpoint), ServerProfile(name: "Render PC", endpoint: "http://192.0.2.10:8188")]
        observedStarts[running[0].id] = Date().addingTimeInterval(-124)
        monitoredServers = [
            MonitoredServer(endpoint: endpoint, name: "Studio Mac", state: .connected, runningCount: 1, pendingCount: 1,
                currentJobTitle: running[0].title, checkedAt: Date()),
            MonitoredServer(endpoint: profiles[1].endpoint, name: "Render PC", state: .connected, checkedAt: Date())
        ]
        if CommandLine.arguments.contains("--many-servers") {
            monitoredServers += [
                MonitoredServer(endpoint: "https://8080-demo-instance.gputw.ai", name: "GPUtw · Video", state: .connected, runningCount: 1, pendingCount: 8, checkedAt: Date()),
                MonitoredServer(endpoint: "http://192.0.2.11:8188", name: "Animation Mac", state: .connected, checkedAt: Date(), becameAvailableAt: Date().addingTimeInterval(-180)),
                MonitoredServer(endpoint: "http://192.0.2.12:8188", name: "Render workstation · West studio", state: .disconnected),
                MonitoredServer(endpoint: "https://8090-demo-other.gputw.ai", name: "GPUtw · Overnight", state: .signInRequired),
                MonitoredServer(endpoint: "http://192.0.2.13:8188", name: "Video PC", state: .connected, pendingCount: 3, checkedAt: Date()),
                MonitoredServer(endpoint: "http://192.0.2.14:8188", name: "Studio backup", state: .checking)
            ]
        }
        #else
        endpoint = UserDefaults.standard.string(forKey: "comfyEndpoint") ?? "http://127.0.0.1:8188"
        if let data = UserDefaults.standard.data(forKey: "serverProfiles"), let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) { profiles = saved }
        notificationMode = UserDefaults.standard.string(forKey: "notificationMode") ?? "off"
        notifyProblems = UserDefaults.standard.bool(forKey: "notifyProblems")
        notifyAvailability = UserDefaults.standard.bool(forKey: "notifyAvailability")
        serverMonitor.onUpdate = { [weak self] in self?.monitoredServers = $0 }
        serverMonitor.onAvailable = { [weak self] server in
            guard self?.notifyAvailability == true else { return }
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Server available"),
                body: server.name + " · " + L10n.text("Queue is empty. Ready for the next batch."))
        }
        serverMonitor.onDisconnected = { [weak self] server in
            guard self?.notifyProblems == true else { return }
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Server disconnected"), body: server.name)
        }
        rememberMonitoredServer(endpoint)
        configureServerMonitor()
        let refreshTimer = Timer(timeInterval: Self.connectionRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        self.refreshTimer = refreshTimer
        let progressTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshProgress() }
        }
        RunLoop.main.add(progressTimer, forMode: .common)
        self.progressTimer = progressTimer
        agentIntegrationEnabled = UserDefaults.standard.bool(forKey: "agentIntegrationEnabled")
        Task { await NotificationService.shared.refreshAuthorizationStatus() }
        configureAgentBridge()
        let agentTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMonitoringState(); self?.serverMonitor.publish(); self?.tickAgentBridge() }
        }
        RunLoop.main.add(agentTimer, forMode: .common)
        self.agentTimer = agentTimer
        Task { await refresh() }
        #endif
    }

    func setupAgents() async {
        guard !isSettingUpAgents, let script = Bundle.main.url(forResource: "server", withExtension: "py", subdirectory: "AgentBridge") else { return }
        let skill = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "AgentBridge/skills/comfyqueuebar")
        isSettingUpAgents = true
        defer { isSettingUpAgents = false }
        agentSetupMessage = nil
        let outcome = await Task.detached { () -> Result<AgentSetup.Report, Error> in
            do {
                let python = AgentSetup.python()
                let customHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                return .success(try AgentSetup.configure(script: script, python: python, codex: AgentSetup.codex(), codexHome: customHome, skill: skill))
            } catch { return .failure(error) }
        }.value
        switch outcome {
        case .success(let report):
            if !report.configured.isEmpty { agentIntegrationEnabled = true }
            var messages: [String] = []
            if !report.configured.isEmpty { messages.append(L10n.text("Configured %@. Reopen your agent chats.", report.configured.joined(separator: ", "))) }
            if !report.skillsInstalled.isEmpty { messages.append(L10n.text("Installed ComfyQueueBar skill for %@.", report.skillsInstalled.joined(separator: ", "))) }
            messages.append(contentsOf: report.failed)
            agentSetupMessage = messages.joined(separator: "\n")
        case .failure(let error): agentSetupMessage = error.localizedDescription
        }
    }

    private func configureAgentBridge() {
        #if !DOCUMENTATION_SCREENSHOT
        if agentIntegrationEnabled {
            do { agentBridge = try AgentBridge(); agentBridgeError = nil; tickAgentBridge() }
            catch { agentBridgeError = error.localizedDescription }
        } else { agentBridge?.stop(); agentBridge = nil; agentBridgeError = nil }
        #endif
    }

    private func tickAgentBridge() {
        guard let bridge = agentBridge else { return }
        do {
            try bridge.tick(endpoint: endpoint, connected: isConnected, historyAvailable: !historyUnavailable,
                lastUpdated: lastUpdated, running: running.map(\.id), pending: pending.map(\.id),
                notificationMode: notificationMode, notifyProblems: notifyProblems, notifyAvailability: notifyAvailability,
                notificationAuthorization: NotificationService.shared.authorizationStatus,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
            agentBridgeError = nil
            let requests = bridge.takeRefreshRequests()
            for request in requests { Task { await performRefreshJob(request) } }
        } catch { agentBridgeError = error.localizedDescription }
    }

    private func ingestAgentHistory(_ history: [String: Any], endpoint source: String) {
        guard let bridge = agentBridge else { return }
        var results: [String: AgentJobResult] = [:]
        for job in CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: history.count, title: Self.jobTitle) {
            results[job.id] = AgentJobResult(status: "completed", outputs: job.outputs.map {
                ["filename": $0.filename, "subfolder": $0.subfolder, "type": $0.type,
                 "url": $0.url(endpoint: source)?.absoluteString ?? ""]
            }, source: "history_list", last_verified_at: Date().timeIntervalSince1970)
        }
        for job in HistoryDetails.failures(history, title: Self.jobTitle) {
            results[job.id] = AgentJobResult(status: job.interrupted ? "interrupted" : "failed", error: job.reason,
                source: "history_list", last_verified_at: Date().timeIntervalSince1970)
        }
        do { try bridge.ingest(endpoint: source, results: results) }
        catch { agentBridgeError = error.localizedDescription }
    }

    private func performRefreshJob(_ refresh: AgentRefreshRequest) async {
        guard refresh.endpoint == endpoint, let bridge = agentBridge else { return }
        let generation = connectionGeneration
        var queueResult: [String: Any] = ["checked": false]
        var historyResult: [String: Any] = ["checked": false]
        var status = "unknown"
        var reason = "history_entry_missing"
        var outputs: [[String: String]] = []

        do {
            let data = try await requestData(path: "queue")
            guard refresh.endpoint == endpoint, generation == connectionGeneration else { return }
            let queue = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let isRunning = Self.parseJobs(queue["queue_running"]).contains { $0.id == refresh.prompt_id }
            let isPending = Self.parseJobs(queue["queue_pending"]).contains { $0.id == refresh.prompt_id }
            queueResult = ["checked": true, "running": isRunning, "queued": isPending]
            if isRunning { status = "running"; reason = "" }
            else if isPending { status = "queued"; reason = "" }
        } catch {
            queueResult = ["checked": true, "error": error.localizedDescription]
        }

        do {
            let data = try await requestData(path: "history/" + refresh.prompt_id)
            guard refresh.endpoint == endpoint, generation == connectionGeneration else { return }
            guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw QueueError.invalidResponse
            }
            guard let entry = dictionary[refresh.prompt_id] as? [String: Any] else {
                historyResult = ["checked": true, "found": false]
                if status == "unknown" { reason = "history_entry_missing" }
                try bridge.completeRefreshJob(refresh, result: refreshDiagnostic(refresh, status: status, reason: reason,
                    queue: queueResult, history: historyResult, outputs: outputs))
                return
            }
            historyResult = ["checked": true, "found": true]
            let one = [refresh.prompt_id: entry]
            if let completed = CompletionHistory.parse(one, now: Date(), maxAge: nil, limit: 1, title: Self.jobTitle).first {
                status = "completed"
                outputs = completed.outputs.map { ["filename": $0.filename, "subfolder": $0.subfolder, "type": $0.type,
                    "url": $0.url(endpoint: refresh.endpoint)?.absoluteString ?? ""] }
                reason = ""
                ingestAgentHistory(one, endpoint: refresh.endpoint)
            } else if let failed = HistoryDetails.failures(one, title: Self.jobTitle).first {
                status = failed.interrupted ? "interrupted" : "failed"
                reason = failed.reason
                ingestAgentHistory(one, endpoint: refresh.endpoint)
            } else if status == "unknown" {
                reason = "history_status_unrecognized"
            }
        } catch {
            historyResult = ["checked": true, "error": error.localizedDescription]
            if status == "unknown" { reason = "history_query_failed: " + error.localizedDescription }
        }
        try? bridge.completeRefreshJob(refresh, result: refreshDiagnostic(refresh, status: status, reason: reason,
            queue: queueResult, history: historyResult, outputs: outputs))
    }

    private func refreshDiagnostic(_ request: AgentRefreshRequest, status: String, reason: String,
                                   queue: [String: Any], history: [String: Any], outputs: [[String: String]]) -> [String: Any] {
        ["request_id": request.request_id, "prompt_id": request.prompt_id, "status": status,
         "source": "queue_and_history", "last_verified_at": Date().timeIntervalSince1970,
         "unknown_reason": reason.isEmpty ? NSNull() : reason as NSString,
         "queue_result": queue, "history_result": history, "endpoint": request.endpoint,
         "server_name": serverName, "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
         "bridge_version": "0.2.0", "outputs": outputs]
    }

    var serverName: String { profiles.first { $0.endpoint == endpoint }?.name ?? (URLComponents(string: endpoint)?.host ?? endpoint) }
    var canChangeServer: Bool { movingJobID == nil && stoppingJobID == nil }

    func signInToGPUTW(address: String) {
        guard canChangeServer, !isClearingGPUTW else { return }
        GPUTWLoginWindow.shared.open(address: address) { [weak self] address in
            guard let self, self.canChangeServer else { return }
            let port = URL(string: address)?.host?.split(separator: "-").first.map(String.init) ?? ""
            let name = self.profiles.first(where: { $0.endpoint == address })?.name ?? "GPUtw · " + port
            self.reviewConnection(to: address, profileName: name, fromGPUTW: true)
        }
    }

    func reviewConnection(to address: String, profileName: String? = nil, fromGPUTW: Bool = false) {
        guard canChangeServer, !isClearingGPUTW else { return }
        clearConnectionFeedback()
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), GPUTWAddress.isDashboard(url) { signInToGPUTW(address: value); return }
        do {
            let address = try ConnectionAddress.normalize(value)
            ConnectionReviewWindow.shared.open(address: address) { [weak self] selected in
                guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                if fromGPUTW {
                    let name = self.profiles.first(where: { $0.endpoint == selected })?.name
                        ?? "GPUtw · " + ConnectionAddress.port(selected)
                    self.saveProfile(name: name, address: selected)
                } else if let profileName {
                    self.saveProfile(name: profileName, address: selected)
                }
                if fromGPUTW { GPUTWLoginWindow.shared.close() }
                Task { await self.connect(to: selected) }
            } onOpenAlternative: { [weak self] alternative in
                guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                GPUTWLoginWindow.shared.open(address: alternative) { [weak self] service in
                    guard let self, self.canChangeServer, !self.isClearingGPUTW else { return }
                    self.reviewConnection(to: service, fromGPUTW: true)
                }
            }
        } catch {
            connectionMessage = error.localizedDescription
            connectionMessageIsError = true
        }
    }

    func clearGPUTWLogin() async {
        guard canChangeServer, !isClearingGPUTW else { return }
        isClearingGPUTW = true
        defer { isClearingGPUTW = false }
        GPUTWLoginWindow.shared.close()
        ConnectionReviewWindow.shared.close()
        ComfyHTTPClient.shared.beginClearingAuthentication()
        serverMonitor.clearGPUTWAuthentication()
        defer { ComfyHTTPClient.shared.finishClearingAuthentication() }
        let isGPUTW = URL(string: endpoint).flatMap { GPUTWAddress.serviceOrigin($0) } != nil
        if isGPUTW {
            connectionGeneration = UUID()
            setDisconnected(L10n.text("GPUtw sign-in cleared."), requiresSignIn: true)
        }
        // This is this app's WebKit store, never Safari/Chrome's browsing data.
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        connectionMessage = L10n.text("GPUtw sign-in cleared.")
        connectionMessageIsError = false
    }

    @discardableResult
    func saveProfile(name: String, address: String) -> Bool {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), GPUTWAddress.isDashboard(url) {
            signInToGPUTW(address: value)
            return false
        }
        let address: String
        do { address = try ConnectionAddress.normalize(value) }
        catch {
            connectionMessage = L10n.text("Enter a valid http:// or https:// address.")
            connectionMessageIsError = true
            return false
        }
        guard let url = URLComponents(string: address) else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? (url.host ?? address) : name
        if let index = profiles.firstIndex(where: { $0.endpoint == address }) {
            if !name.isEmpty { profiles[index].name = label }
        }
        else { profiles.append(ServerProfile(name: label, endpoint: address)) }
        persistProfiles()
        connectionMessage = L10n.text("Address saved")
        connectionMessageIsError = false
        return true
    }
    /// Selection is independent of membership. Only this explicit action removes a monitor.
    func deleteProfile(_ id: UUID) {
        guard canChangeServer, !isClearingGPUTW,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        if MultiServerMonitor.key(endpoint) == MultiServerMonitor.key(profile.endpoint),
           !profiles.contains(where: { MultiServerMonitor.key($0.endpoint) == MultiServerMonitor.key(endpoint) }) {
            changeSelectedEndpoint(to: profiles.first?.endpoint ?? "")
            Task { await refresh(forceHistory: true) }
        }
        persistProfiles()
    }

    /// Adopt the legacy/current connection and newly connected addresses into the
    /// durable monitor list so selecting another server cannot discard them.
    private func rememberMonitoredServer(_ address: String) {
        #if !DOCUMENTATION_SCREENSHOT
        guard let normalized = try? ConnectionAddress.normalize(address), let url = URL(string: normalized),
              !GPUTWAddress.isDashboard(url),
              !profiles.contains(where: { MultiServerMonitor.key($0.endpoint) == normalized }) else { return }
        let localHosts = ["127.0.0.1", "localhost", "::1", "[::1]"]
        let name = localHosts.contains(url.host?.lowercased() ?? "") ? L10n.text("This Mac")
            : GPUTWAddress.serviceOrigin(url) != nil ? "GPUtw · " + ConnectionAddress.port(normalized)
            : url.host ?? normalized
        profiles.append(ServerProfile(name: name, endpoint: normalized))
        persistProfiles()
        #endif
    }

    func saveWakeSettings(_ settings: WakeSettings, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        do {
            try WakeOnLAN.validate(settings)
            profiles[index].wake = settings
            persistProfiles()
            wakeMessages[id] = L10n.text("Wake settings saved")
        } catch { wakeMessages[id] = L10n.text(error.localizedDescription) }
    }

    func wakeServer(_ id: UUID, automatically: Bool = false) {
        guard let profile = profiles.first(where: { $0.id == id }), let settings = profile.wake else { return }
        let now = Date()
        if automatically {
            guard settings.automaticallyWake,
                  WakeOnLAN.canRetry(lastAttempt: lastWakeAttempts[id], now: now) else { return }
        }
        lastWakeAttempts[id] = now
        do {
            try WakeOnLAN.send(settings)
            wakeMessages[id] = L10n.text("Wake packet sent. Waiting for ComfyUI to reconnect.")
        } catch { wakeMessages[id] = L10n.text(error.localizedDescription) }
    }

    func installProgressExtension(in comfyRoot: URL) {
        progressExtensionMessage = nil
        progressExtensionError = nil
        let manager = FileManager.default
        let customNodes = comfyRoot.appendingPathComponent("custom_nodes", isDirectory: true)
        let destination = customNodes.appendingPathComponent("ComfyQueueBarProgress", isDirectory: true)
        guard manager.fileExists(atPath: customNodes.path) else {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", "custom_nodes folder not found")
            return
        }
        guard !manager.fileExists(atPath: destination.path) else {
            progressExtensionError = L10n.text("The progress extension already exists at %@. Remove or back it up before installing again.", destination.path)
            return
        }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("ComfyQueueBarProgress", isDirectory: true),
              manager.fileExists(atPath: source.appendingPathComponent("__init__.py").path) else {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", "extension files are missing from the app")
            return
        }
        do {
            try ProgressExtensionInstaller.install(from: source, to: destination)
            progressExtensionMessage = L10n.text("Progress extension installed. Finish any active generation, then restart ComfyUI.")
        } catch {
            progressExtensionError = L10n.text("Could not install the progress extension: %@", error.localizedDescription)
        }
    }
    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "serverProfiles") }
        refreshServers()
    }
    func authorizeNotifications() async {
        await NotificationService.shared.authorize()
        permissionMessage = NotificationService.shared.permissionMessage
    }
    private func processHistoryNotifications(ids: Set<String>) {
        let delta = notificationTracker.ingest(ids: ids, successes: Set(completed.map(\.id)), failures: Set(failures.filter { !$0.interrupted }.map(\.id)), queueCount: totalJobs)
        if notificationMode == "each" {
            for job in completed where delta.successes.contains(job.id) {
                NotificationService.shared.send(id: endpoint + job.id, title: L10n.text("Job completed"), body: serverName + " · " + job.title)
            }
        }
        if notifyProblems {
            for job in failures where delta.failures.contains(job.id) {
                NotificationService.shared.send(id: endpoint + job.id, title: L10n.text("Job failed"), body: serverName + " · " + job.title + "\n" + job.reason)
            }
        }
        if let batch = delta.batch, notificationMode == "batch" {
            NotificationService.shared.send(id: UUID().uuidString, title: L10n.text("Queue finished"), body: serverName + " · " + L10n.text("%@ completed · %@ failed", String(batch.completed), String(batch.failed)))
        }
    }
    func timingText(for job: QueueJob, now: Date) -> String {
        guard let observed = observedStarts[job.id] else { return L10n.text("Estimating…") }
        let elapsed = max(0, now.timeIntervalSince(observed))
        let elapsedText = Self.durationText(elapsed)
        guard let duration = HistoryDetails.estimatedDuration(fingerprint: HistoryDetails.fingerprint(job.prompt), completed: completed) else {
            return L10n.text("Observed %@ · estimate unavailable", elapsedText)
        }
        let remaining = duration - elapsed
        if remaining <= 0 { return L10n.text("Observed %@ · past estimated duration", elapsedText) }
        return L10n.text("Observed %@ · estimated %@ remaining", elapsedText, Self.durationText(remaining))
    }
    static func durationText(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }

    func connect(to value: String) async {
        guard canChangeServer else { return }
        clearConnectionFeedback()
        actionMessage = nil
        actionIsError = false
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: cleaned) {
            if GPUTWAddress.isDashboard(url) { signInToGPUTW(address: cleaned); return }
            if let origin = GPUTWAddress.serviceOrigin(url) { cleaned = origin.absoluteString }
        }
        cleaned = (try? ConnectionAddress.normalize(cleaned)) ?? cleaned
        changeSelectedEndpoint(to: cleaned)
        rememberMonitoredServer(cleaned)
        await refresh(forceHistory: true)
    }

    private func changeSelectedEndpoint(to cleaned: String) {
        if endpoint != cleaned {
            connectionGeneration = UUID()
            secondaryRefreshTask?.cancel()
            secondaryRefreshTask = nil
            secondaryRefreshForceHistory = false
            secondaryRefreshToken = UUID()
            clearPairedPortCheck(resetThrottle: true)
            completed = []; failures = []; running = []; pending = []; observedStarts = [:]
            queueProgress = nil
            progressBridgeStatus = .checking
            notificationTracker = NotificationTracker()
            isConnected = false
            needsSignIn = false
            lastUpdated = nil
            errorMessage = nil
            monitoringState = .checking
            lastHistoryPoll = nil
            historyUnavailable = false
        }
        endpoint = cleaned
        UserDefaults.standard.set(cleaned, forKey: "comfyEndpoint")
    }

    private func clearConnectionFeedback() {
        connectionMessage = nil
        connectionMessageIsError = false
    }

    func refresh(forceHistory: Bool = false) async {
        refreshServers()
        guard hasSelectedServer, !isLoading, !isClearingGPUTW, movingJobID == nil, stoppingJobID == nil else { return }
        isLoading = true
        updateMonitoringState()
        let generation = connectionGeneration
        defer {
            isLoading = false
            updateMonitoringState()
            if generation != connectionGeneration { Task { await refresh(forceHistory: true) } }
        }

        do {
            let snapshot = try await fetchQueue()
            guard generation == connectionGeneration else { return }
            apply(snapshot)
            isConnected = true
            needsSignIn = false
            errorMessage = nil
            lastUpdated = Date()
            updateMonitoringState()
            serverMonitor.record(endpoint, running: running, pending: pending, checkedAt: lastUpdated ?? Date())
            schedulePairedPortCheck(generation: generation)
            // Queue state is the primary monitor. Progress and history are
            // enrichment and must not hold isLoading across their network
            // requests; otherwise a slow history endpoint blocks the next
            // four-second queue retry.
            scheduleSecondaryRefresh(generation: generation, forceHistory: forceHistory)
        } catch {
            guard generation == connectionGeneration else { return }
            clearPairedPortCheck(resetThrottle: true)
            setDisconnected(error.localizedDescription, requiresSignIn: MonitoringState.requiresSignIn(error))
            serverMonitor.recordFailure(endpoint, error)
            if WakeOnLAN.isOfflineError(error),
               let profile = profiles.first(where: { $0.endpoint == endpoint }) {
                wakeServer(profile.id, automatically: true)
            }
        }
    }

    private func scheduleSecondaryRefresh(generation: UUID, forceHistory: Bool) {
        guard generation == connectionGeneration else { return }
        secondaryRefreshForceHistory = secondaryRefreshForceHistory || forceHistory
        guard secondaryRefreshTask == nil else { return }

        let token = UUID()
        secondaryRefreshToken = token
        let requestedForceHistory = secondaryRefreshForceHistory
        secondaryRefreshForceHistory = false
        secondaryRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.secondaryRefreshToken == token {
                    self.secondaryRefreshTask = nil
                    if self.secondaryRefreshForceHistory {
                        self.scheduleSecondaryRefresh(generation: self.connectionGeneration, forceHistory: true)
                    }
                }
            }
            await self.refreshProgress(forceBridgeCheck: true)
            guard !Task.isCancelled, self.connectionGeneration == generation else { return }
            await self.refreshHistory(force: requestedForceHistory)
        }
    }

    private func schedulePairedPortCheck(generation: UUID) {
        guard isConnected, let url = URL(string: endpoint),
              let paired = GPUTWAddress.pairedServiceOrigin(url) else {
            clearPairedPortCheck(resetThrottle: true)
            return
        }
        guard running.isEmpty, pending.isEmpty else {
            clearPairedPortCheck(resetThrottle: true)
            return
        }
        let source = endpoint
        let pairedAddress = paired.absoluteString
        if pairedPortEndpoint != pairedAddress {
            clearPairedPortCheck(resetThrottle: true)
            pairedPortEndpoint = pairedAddress
        }
        guard pairedPortCheckTask == nil else { return }
        if let lastPairedPortCheck, Date().timeIntervalSince(lastPairedPortCheck) < 30 { return }

        lastPairedPortCheck = Date()
        pairedQueueStatus = .checking
        let token = UUID()
        pairedPortCheckToken = token
        pairedPortCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pairedPortCheckToken == token { self.pairedPortCheckTask = nil }
            }
            do {
                let inspection = try await ConnectionInspector.inspectQueue(pairedAddress, timeout: 4)
                guard !Task.isCancelled, self.pairedPortCheckToken == token,
                      self.connectionGeneration == generation, self.endpoint == source,
                      self.isConnected, self.running.isEmpty, self.pending.isEmpty else { return }
                if inspection.isIdle {
                    self.pairedQueueStatus = .empty
                } else {
                    let firstJob = inspection.running.first ?? inspection.pending.first
                    self.pairedQueueStatus = .work(running: inspection.running.count,
                        waiting: inspection.pending.count, title: firstJob?.title)
                }
            } catch {
                guard !Task.isCancelled, self.pairedPortCheckToken == token,
                      self.connectionGeneration == generation, self.endpoint == source,
                      self.isConnected, self.running.isEmpty, self.pending.isEmpty else { return }
                self.pairedQueueStatus = .issue(PairedPortIssue.classify(error))
            }
        }
    }

    private func clearPairedPortCheck(resetThrottle: Bool) {
        pairedPortCheckToken = UUID()
        pairedPortCheckTask?.cancel()
        pairedPortCheckTask = nil
        pairedPortEndpoint = nil
        pairedQueueStatus = nil
        if resetThrottle { lastPairedPortCheck = nil }
    }

    func retryPairedPortCheck() {
        lastPairedPortCheck = nil
        schedulePairedPortCheck(generation: connectionGeneration)
    }

    private func refreshHistory(force: Bool) async {
        guard force || lastHistoryPoll.map({ Date().timeIntervalSince($0) >= 15 }) ?? true else { return }
        lastHistoryPoll = Date()
        let source = endpoint
        let generation = connectionGeneration
        var bulkHistoryIDs: Set<String> = []
        do {
            let data = try await requestData(path: "history", queryItems: [URLQueryItem(name: "max_items", value: "200")])
            guard let history = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueueError.invalidResponse }
            guard source == endpoint, generation == connectionGeneration else { return }
            bulkHistoryIDs = Set(history.keys)
            completed = CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: 200, title: Self.jobTitle)
            failures = HistoryDetails.failures(history, title: Self.jobTitle)
            processHistoryNotifications(ids: Set(history.keys))
            historyUnavailable = false
            ingestAgentHistory(history, endpoint: source)
        } catch {
            guard source == endpoint, generation == connectionGeneration else { return }
            // History errors never disconnect a working queue or imply that jobs completed.
            historyUnavailable = true
        }
        // Targeted lookups recover subscribed jobs even when the bulk endpoint
        // is unavailable or omits them from its bounded result set.
        await refreshSubscribedHistory(source: source, generation: generation, knownHistoryIDs: bulkHistoryIDs)
    }

    private func refreshSubscribedHistory(source: String, generation: UUID, knownHistoryIDs: Set<String>) async {
        guard let bridge = agentBridge else { return }
        let queued = Set((running + pending).map(\.id))
        let ids = bridge.historyCandidates(endpoint: source, queued: queued)
        await withTaskGroup(of: (String, Data?).self) { group in
            for id in ids where !knownHistoryIDs.contains(id) {
                group.addTask { [weak self] in
                    guard let self else { return (id, nil) }
                    return (id, try? await self.requestData(path: "history/" + id))
                }
            }
            for await (id, data) in group {
                guard source == endpoint, generation == connectionGeneration, let data,
                      let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any], entry[id] != nil else { continue }
                ingestAgentHistory(entry, endpoint: source)
            }
        }
    }

    func refreshProgress(forceBridgeCheck: Bool = false) async {
        guard !isProgressLoading else { return }
        guard isConnected, let job = running.first else {
            queueProgress = nil
            return
        }
        if progressBridgeStatus == .missing && !forceBridgeCheck { return }

        isProgressLoading = true
        let generation = connectionGeneration
        defer { isProgressLoading = false }

        do {
            let data = try await requestData(path: "comfyqueuebar/queue-progress")
            let snapshot = try JSONDecoder().decode(QueueProgress.self, from: data)
            // The queue can change while this request is in flight. Never let
            // a response for the previous running prompt overwrite the new
            // job's progress state.
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .available
            queueProgress = snapshot.promptID == job.id ? snapshot : nil
        } catch QueueError.serverStatus(let status, _) where status == 404 {
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .missing
            queueProgress = nil
        } catch {
            guard generation == connectionGeneration, running.first?.id == job.id else { return }
            progressBridgeStatus = .error
            queueProgress = nil
        }
    }

    func moveToFront(_ requestedJob: QueueJob) async {
        guard hasFreshQueue, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        movingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false
        let generation = connectionGeneration
        var originalID: String?
        var originalShortID = requestedJob.shortID
        var replacementID: String?

        do {
            let before = try await fetchQueue()
            let currentPending = Self.parseJobs(before["queue_pending"])
            guard let job = currentPending.first(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerPending
            }
            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            originalID = job.id
            originalShortID = job.shortID

            let submittedData = try await requestData(
                path: "prompt",
                method: "POST",
                body: ["prompt": job.prompt, "extra_data": job.extraData, "front": true]
            )
            guard let submitted = try JSONSerialization.jsonObject(with: submittedData) as? [String: Any],
                  let newID = submitted["prompt_id"] as? String else {
                throw QueueError.invalidResponse
            }
            replacementID = newID

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            let afterSubmit = try await fetchQueue()
            let originalStarted = Self.parseJobs(afterSubmit["queue_running"]).contains { $0.id == job.id }
            if originalStarted {
                throw QueueError.jobAlreadyRunning
            }

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            try await deletePendingJob(id: job.id)
            let afterDelete = try await fetchQueue()
            let oldStillPending = Self.parseJobs(afterDelete["queue_pending"]).contains { $0.id == job.id }
            let oldNowRunning = Self.parseJobs(afterDelete["queue_running"]).contains { $0.id == job.id }
            if oldNowRunning { throw QueueError.jobAlreadyRunning }
            if oldStillPending { throw QueueError.originalStillPending }

            actionMessage = L10n.text("Moved to the front of the waiting queue. New job ID: %@", String(String(newID.prefix(8))))
        } catch {
            if let originalID, let replacementID, generation == connectionGeneration {
                let recovery = await recoverSubmission(
                    originalID: originalID,
                    originalShortID: originalShortID,
                    replacementID: replacementID,
                    reason: error.localizedDescription
                )
                actionMessage = recovery.message
                actionIsError = recovery.isError
            } else {
                actionMessage = error.localizedDescription
                actionIsError = true
            }
        }

        movingJobID = nil
        await refresh()
    }

    func stopRunning(_ requestedJob: QueueJob) async {
        guard hasFreshQueue, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        let generation = connectionGeneration
        stoppingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false

        do {
            let snapshot = try await fetchQueue()
            let currentRunning = Self.parseJobs(snapshot["queue_running"])
            guard currentRunning.contains(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerRunning
            }

            guard generation == connectionGeneration else { throw QueueError.serverChanged }
            _ = try await requestData(path: "interrupt", method: "POST", body: ["prompt_id": requestedJob.id])

            var stopped = false
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard generation == connectionGeneration else { throw QueueError.serverChanged }
                let updated = try await fetchQueue()
                apply(updated)
                isConnected = true
                needsSignIn = false
                errorMessage = nil
                lastUpdated = Date()
                updateMonitoringState()
                if !Self.parseJobs(updated["queue_running"]).contains(where: { $0.id == requestedJob.id }) {
                    stopped = true
                    break
                }
            }

            if stopped {
                actionMessage = L10n.text("The job has stopped. The next waiting job can now run.")
            } else {
                actionMessage = L10n.text("Stop requested. ComfyUI has not yet reported that the job ended.")
                actionIsError = true
            }
        } catch {
            actionMessage = error.localizedDescription
            actionIsError = true
        }

        stoppingJobID = nil
        await refresh()
    }

    private func recoverSubmission(
        originalID: String,
        originalShortID: String,
        replacementID: String,
        reason: String
    ) async -> (message: String, isError: Bool) {
        let replacementShortID = String(replacementID.prefix(8))
        guard let snapshot = try? await fetchQueue() else {
            return (L10n.text("Could not confirm the result. Refresh and check original ID %@ and new ID %@.", originalShortID, replacementShortID) + "\n" + reason, true)
        }

        let originalPending = Self.parseJobs(snapshot["queue_pending"]).contains { $0.id == originalID }
        let originalRunning = Self.parseJobs(snapshot["queue_running"]).contains { $0.id == originalID }
        let replacementPending = Self.parseJobs(snapshot["queue_pending"]).contains { $0.id == replacementID }
        let replacementRunning = Self.parseJobs(snapshot["queue_running"]).contains { $0.id == replacementID }

        if originalRunning {
            if replacementPending {
                try? await deletePendingJob(id: replacementID)
                if let afterCleanup = try? await fetchQueue(),
                   !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                    return (L10n.text("The original job started. The resubmitted entry was removed; the running job was not interrupted."), false)
                }
            }
            return (L10n.text("Could not confirm duplicate cleanup. Refresh now and check original ID %@ and new ID %@.", String(originalShortID), String(replacementShortID)), true)
        }

        if originalPending {
            if !replacementRunning {
                try? await deletePendingJob(id: originalID)
                if let afterRetry = try? await fetchQueue() {
                    let originalStillPending = Self.parseJobs(afterRetry["queue_pending"]).contains { $0.id == originalID }
                    let originalNowRunning = Self.parseJobs(afterRetry["queue_running"]).contains { $0.id == originalID }
                    if !originalStillPending && !originalNowRunning {
                        return (L10n.text("Moved to the front of the waiting queue. New job ID: %@", String(replacementShortID)), false)
                    }
                }
            }

            if replacementPending {
                try? await deletePendingJob(id: replacementID)
                if let afterCleanup = try? await fetchQueue(),
                   !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                    return (L10n.text("Prioritization failed. The resubmitted entry was removed; the original job remains queued."), true)
                }
            }
            return (L10n.text("Could not confirm prioritization or cleanup. Refresh now and check original ID %@ and new ID %@.", String(originalShortID), String(replacementShortID)), true)
        }

        if replacementPending {
            try? await deletePendingJob(id: replacementID)
            if let afterCleanup = try? await fetchQueue(),
               !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                return (L10n.text("The original job left the waiting queue. The resubmitted entry was removed."), false)
            }
        }

        if replacementRunning {
            return (L10n.text("The original job status is unknown, but the resubmitted job started. Refresh and check IDs %@ and %@.", String(originalShortID), String(replacementShortID)), true)
        }
        return (L10n.text("The original job left the waiting queue. Refresh to check the result.") + "\n" + reason, true)
    }

    private func fetchQueue() async throws -> [String: Any] {
        let data = try await requestData(path: "queue")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ComfyQueuePayload.isValid(object) else {
            throw QueueError.invalidResponse
        }
        return object
    }

    private func requestData(path: String, method: String = "GET", body: [String: Any]? = nil, queryItems: [URLQueryItem] = []) async throws -> Data {
        #if DOCUMENTATION_SCREENSHOT
        throw QueueError.invalidEndpoint // Documentation builds never contact a server.
        #else
        guard var components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil else {
            throw QueueError.invalidEndpoint
        }

        let basePath = components.path.split(separator: "/").joined(separator: "/")
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        guard let url = components.url else { throw QueueError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await ComfyHTTPClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = String(data: data.prefix(400), encoding: .utf8)
            throw QueueError.serverStatus(status, detail)
        }
        return data
        #endif
    }

    private func deletePendingJob(id: String) async throws {
        _ = try await requestData(path: "queue", method: "POST", body: ["delete": [id]])
    }

    private func apply(_ snapshot: [String: Any]) {
        running = Self.parseJobs(snapshot["queue_running"])
        pending = Self.parseJobs(snapshot["queue_pending"])
        for job in running where observedStarts[job.id] == nil { observedStarts[job.id] = Date() }
        observedStarts = observedStarts.filter { id, _ in running.contains { $0.id == id } }
        notificationTracker.observeQueue(count: totalJobs)
        if let queueProgress, running.first?.id != queueProgress.promptID {
            self.queueProgress = nil
        }
    }

    private func setDisconnected(_ message: String, requiresSignIn: Bool = false) {
        isConnected = false
        historyUnavailable = true
        running = []
        pending = []
        queueProgress = nil
        errorMessage = message
        needsSignIn = requiresSignIn
        updateMonitoringState()
    }

    static func parseJobs(_ value: Any?) -> [QueueJob] {
        guard let rows = value as? [[Any]] else { return [] }
        return rows.enumerated().compactMap { index, row in
            guard row.count > 1, let promptID = row[1] as? String else { return nil }
            let prompt = row.count > 2 ? row[2] as? [String: Any] ?? [:] : [:]
            let extra = row.count > 3 ? row[3] as? [String: Any] ?? [:] : [:]
            let title = jobTitle(prompt: prompt, extra: extra)
            let nodeCount = prompt.count
            let queueNumber = (row.first as? NSNumber)?.intValue
            return QueueJob(
                id: promptID,
                title: title,
                nodeCount: nodeCount,
                queueNumber: queueNumber,
                position: index + 1,
                prompt: prompt,
                extraData: extra
            )
        }
    }

    static func jobTitle(prompt: [String: Any], extra: [String: Any]) -> String {
        if let pngInfo = extra["extra_pnginfo"] as? [String: Any],
           let workflow = pngInfo["workflow"] as? [String: Any],
           let name = workflow["name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        for node in prompt.values {
            guard let node = node as? [String: Any],
                  let meta = node["_meta"] as? [String: Any],
                  let title = meta["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return title
        }

        for node in prompt.values {
            guard let node = node as? [String: Any],
                  let inputs = node["inputs"] as? [String: Any] else { continue }
            for key in ["filename_prefix", "file_prefix"] {
                if let value = displayValue(inputs[key]), !value.isEmpty { return value }
            }
        }
        return L10n.text("ComfyUI workflow")
    }

    private static func displayValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let object = value as? [String: Any], let text = object["value"] as? String { return text }
        return nil
    }
}
