import AppKit
import Foundation
import SwiftUI

@MainActor
final class QueueViewModel: ObservableObject {
    @Published var endpoint: String
    @Published private(set) var running: [QueueJob] = []
    @Published private(set) var pending: [QueueJob] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isLoading = false
    @Published private(set) var movingJobID: String?
    @Published private(set) var stoppingJobID: String?
    @Published private(set) var queueProgress: QueueProgress?
    @Published private(set) var progressBridgeStatus: ProgressBridgeStatus = .checking
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionMessage: String?
    @Published private(set) var actionIsError = false
    @Published private(set) var lastUpdated: Date?

    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var isProgressLoading = false

    var totalJobs: Int { running.count + pending.count }

    init() {
        #if DOCUMENTATION_SCREENSHOT
        endpoint = "http://127.0.0.1:8188"
        let graph: [String: Any] = ["12": ["_meta": ["title": "KSampler"], "class_type": "KSampler"]]
        running = [QueueJob(id: "8f21a7c4-demo-running", title: "Neon city portrait", nodeCount: 24, queueNumber: 1, position: 1, prompt: graph, extraData: [:])]
        pending = [QueueJob(id: "b390e612-demo-waiting", title: "Product lighting study", nodeCount: 18, queueNumber: 2, position: 1, prompt: [:], extraData: [:])]
        isConnected = true
        progressBridgeStatus = .available
        queueProgress = QueueProgress(promptID: running[0].id, nodeID: "12", value: 21, maxValue: 30, percent: 70, state: "running")
        lastUpdated = Date(timeIntervalSince1970: 1790814600)
        #else
        endpoint = UserDefaults.standard.string(forKey: "comfyEndpoint") ?? "http://127.0.0.1:8188"
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshProgress() }
        }
        Task { await refresh() }
        #endif
    }

    func connect(to value: String) async {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        endpoint = cleaned
        UserDefaults.standard.set(cleaned, forKey: "comfyEndpoint")
        await refresh()
    }

    func refresh() async {
        guard !isLoading, movingJobID == nil, stoppingJobID == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await fetchQueue()
            apply(snapshot)
            isConnected = true
            errorMessage = nil
            lastUpdated = Date()
            await refreshProgress(forceBridgeCheck: true)
        } catch {
            setDisconnected(error.localizedDescription)
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
        defer { isProgressLoading = false }

        do {
            let data = try await requestData(path: "comfyqueuebar/queue-progress")
            let snapshot = try JSONDecoder().decode(QueueProgress.self, from: data)
            progressBridgeStatus = .available
            queueProgress = snapshot.promptID == job.id ? snapshot : nil
        } catch QueueError.serverStatus(let status, _) where status == 404 {
            progressBridgeStatus = .missing
            queueProgress = nil
        } catch {
            progressBridgeStatus = .error
            queueProgress = nil
        }
    }

    func moveToFront(_ requestedJob: QueueJob) async {
        guard isConnected, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        movingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false
        var originalID: String?
        var originalShortID = requestedJob.shortID
        var replacementID: String?

        do {
            let before = try await fetchQueue()
            let currentPending = Self.parseJobs(before["queue_pending"])
            guard let job = currentPending.first(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerPending
            }
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

            let afterSubmit = try await fetchQueue()
            let originalStarted = Self.parseJobs(afterSubmit["queue_running"]).contains { $0.id == job.id }
            if originalStarted {
                throw QueueError.jobAlreadyRunning
            }

            try await deletePendingJob(id: job.id)
            let afterDelete = try await fetchQueue()
            let oldStillPending = Self.parseJobs(afterDelete["queue_pending"]).contains { $0.id == job.id }
            let oldNowRunning = Self.parseJobs(afterDelete["queue_running"]).contains { $0.id == job.id }
            if oldNowRunning { throw QueueError.jobAlreadyRunning }
            if oldStillPending { throw QueueError.originalStillPending }

            actionMessage = "Moved to the front of the waiting queue. New job ID: \(String(newID.prefix(8)))"
        } catch {
            if let originalID, let replacementID {
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
        guard isConnected, movingJobID == nil, stoppingJobID == nil, !isLoading else { return }
        stoppingJobID = requestedJob.id
        actionMessage = nil
        actionIsError = false

        do {
            let snapshot = try await fetchQueue()
            let currentRunning = Self.parseJobs(snapshot["queue_running"])
            guard currentRunning.contains(where: { $0.id == requestedJob.id }) else {
                throw QueueError.jobNoLongerRunning
            }

            _ = try await requestData(path: "interrupt", method: "POST", body: ["prompt_id": requestedJob.id])

            var stopped = false
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let updated = try await fetchQueue()
                apply(updated)
                isConnected = true
                errorMessage = nil
                lastUpdated = Date()
                if !Self.parseJobs(updated["queue_running"]).contains(where: { $0.id == requestedJob.id }) {
                    stopped = true
                    break
                }
            }

            if stopped {
                actionMessage = "The job has stopped. The next waiting job can now run."
            } else {
                actionMessage = "Stop requested. ComfyUI has not yet reported that the job ended."
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
            return ("Could not confirm the result. Refresh and check original ID \(originalShortID) and new ID \(replacementShortID)。\n\(reason)", true)
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
                    return ("The original job started. The resubmitted entry was removed; the running job was not interrupted.", false)
                }
            }
            return ("Could not confirm duplicate cleanup. Refresh now and check original ID \(originalShortID) and new ID \(replacementShortID)。", true)
        }

        if originalPending {
            if !replacementRunning {
                try? await deletePendingJob(id: originalID)
                if let afterRetry = try? await fetchQueue() {
                    let originalStillPending = Self.parseJobs(afterRetry["queue_pending"]).contains { $0.id == originalID }
                    let originalNowRunning = Self.parseJobs(afterRetry["queue_running"]).contains { $0.id == originalID }
                    if !originalStillPending && !originalNowRunning {
                        return ("Moved to the front of the waiting queue. New job ID: \(replacementShortID)", false)
                    }
                }
            }

            if replacementPending {
                try? await deletePendingJob(id: replacementID)
                if let afterCleanup = try? await fetchQueue(),
                   !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                    return ("Prioritization failed. The resubmitted entry was removed; the original job remains queued.", true)
                }
            }
            return ("Could not confirm prioritization or cleanup. Refresh now and check original ID \(originalShortID) and new ID \(replacementShortID)。", true)
        }

        if replacementPending {
            try? await deletePendingJob(id: replacementID)
            if let afterCleanup = try? await fetchQueue(),
               !Self.parseJobs(afterCleanup["queue_pending"]).contains(where: { $0.id == replacementID }) {
                return ("The original job left the waiting queue. The resubmitted entry was removed.", false)
            }
        }

        if replacementRunning {
            return ("The original job status is unknown, but the resubmitted job started. Refresh and check IDs \(originalShortID) and \(replacementShortID)。", true)
        }
        return ("The original job left the waiting queue. Refresh to check the result.\n\(reason)", true)
    }

    private func fetchQueue() async throws -> [String: Any] {
        let data = try await requestData(path: "queue")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QueueError.invalidResponse
        }
        return object
    }

    private func requestData(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        #if DOCUMENTATION_SCREENSHOT
        throw QueueError.invalidEndpoint // Documentation builds never contact a server.
        #else
        guard var components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw QueueError.invalidEndpoint
        }

        let basePath = components.path.split(separator: "/").joined(separator: "/")
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw QueueError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
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
        if let queueProgress, running.first?.id != queueProgress.promptID {
            self.queueProgress = nil
        }
    }

    private func setDisconnected(_ message: String) {
        isConnected = false
        running = []
        pending = []
        queueProgress = nil
        errorMessage = message
    }

    private static func parseJobs(_ value: Any?) -> [QueueJob] {
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

    private static func jobTitle(prompt: [String: Any], extra: [String: Any]) -> String {
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
        return "ComfyUI workflow"
    }

    private static func displayValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let object = value as? [String: Any], let text = object["value"] as? String { return text }
        return nil
    }
}

struct QueueJob: Identifiable {
    let id: String
    let title: String
    let nodeCount: Int
    let queueNumber: Int?
    let position: Int
    let prompt: [String: Any]
    let extraData: [String: Any]

    var shortID: String { String(id.prefix(8)) }
}

struct QueueProgress: Decodable {
    let promptID: String?
    let nodeID: String?
    let value: Double?
    let maxValue: Double?
    let percent: Double?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case promptID = "prompt_id"
        case nodeID = "node_id"
        case value
        case maxValue = "max"
        case percent
        case state
    }

    func nodeTitle(for job: QueueJob) -> String {
        guard let nodeID else { return "Waiting for node progress" }
        if let node = job.prompt[nodeID] as? [String: Any],
           let meta = node["_meta"] as? [String: Any],
           let title = meta["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "Node \(nodeID)"
    }
}

enum ProgressBridgeStatus: Equatable {
    case checking
    case available
    case missing
    case error
}

enum QueueError: LocalizedError {
    case invalidEndpoint
    case serverStatus(Int, String?)
    case invalidResponse
    case jobNoLongerPending
    case jobAlreadyRunning
    case jobNoLongerRunning
    case originalStillPending

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter a valid http:// or https:// address."
        case .serverStatus(let status, let detail):
            return "ComfyUI returned HTTP \(status)。" + (detail.map { " \($0)" } ?? "")
        case .invalidResponse: return "ComfyUI returned an unrecognized queue response."
        case .jobNoLongerPending: return "This job is no longer waiting. Refresh and try again."
        case .jobAlreadyRunning: return "The original job started. Prioritization was canceled; the running job will continue."
        case .jobNoLongerRunning: return "This job is no longer running. No stop request was sent."
        case .originalStillPending: return "ComfyUI did not remove the original job. Checking resubmission cleanup."
        }
    }
}

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

#if DOCUMENTATION_SCREENSHOT
@main
struct DocumentationCapture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dark = CommandLine.arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if CommandLine.arguments.contains("--menu-bar") {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            guard let button = status.button else { fatalError("No status button") }
            button.image = QueueBrand.menuBarIcon
            button.imagePosition = .imageLeading
            button.title = " 2"
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.contentView = NSHostingView(rootView: QueuePopover(queue: QueueViewModel()).frame(width: 360, height: 540).clipShape(RoundedRectangle(cornerRadius: 12)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
            panel.setFrameOrigin(NSPoint(x: anchor.midX - 180, y: anchor.minY - 548))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            app.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            withExtendedLifetime((status, panel)) { app.run() }
            return
        }
        let view = NSHostingView(rootView: QueuePopover(queue: QueueViewModel()).frame(width: 360, height: 540))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
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
struct ComfyQueueBarApp: App {
    @StateObject private var queue = QueueViewModel()

    var body: some Scene {
        MenuBarExtra {
            QueuePopover(queue: queue)
                .frame(width: 360, height: 540)
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: QueueBrand.menuBarIcon)
                Text("\(queue.totalJobs)")
                    .monospacedDigit()
            }
            .foregroundStyle(queue.isConnected ? Color.accentColor : Color.secondary)
            .accessibilityLabel("ComfyUI queue: \(queue.totalJobs) jobs")
        }
        .menuBarExtraStyle(.window)
    }
}

#endif

@MainActor
final class QueuePopoverState: ObservableObject {
    @Published var urlInput = ""
    @Published var confirmation: QueueConfirmation?
}

struct QueuePopover: View {
    @ObservedObject var queue: QueueViewModel
    @StateObject private var panel = QueuePopoverState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionSettings
                    summary
                    actionFeedback
                    runningSection
                    pendingSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { panel.urlInput = queue.endpoint }
        .confirmationDialog(panel.confirmation?.title ?? "Confirm action", isPresented: Binding(
            get: { panel.confirmation.map { _ in true } ?? false },
            set: { if !$0 { panel.confirmation = nil } }
        ), titleVisibility: .visible) {
            if let confirmation = panel.confirmation {
                switch confirmation {
                case .prioritize(let job):
                    Button("Prioritize and resubmit") {
                        panel.confirmation = nil
                        Task { await queue.moveToFront(job) }
                    }
                case .stop(let job):
                    Button("Stop running job", role: .destructive) {
                        panel.confirmation = nil
                        Task { await queue.stopRunning(job) }
                    }
                }
            }
            Button("Cancel", role: .cancel) { panel.confirmation = nil }
        } message: {
            Text(panel.confirmation?.message ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            QueueBrand.panelIcon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("ComfyUI Queue")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(queue.isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(queue.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await queue.refresh() }
            } label: {
                Image(systemName: queue.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(queue.isLoading || queue.movingJobID != nil || queue.stoppingJobID != nil)
            .help("Refresh now")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ComfyUI address")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8188", text: $panel.urlInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { Task { await queue.connect(to: panel.urlInput) } }
                Button("Connect") {
                    Task { await queue.connect(to: panel.urlInput) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 9) {
            SummaryTile(title: "Running", count: queue.running.count, tint: .cyan)
            SummaryTile(title: "Waiting", count: queue.pending.count, tint: .orange)
            SummaryTile(title: "Total", count: queue.totalJobs, tint: .purple)
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading("Running", count: queue.running.count, symbol: "waveform.path")
            if !queue.isConnected {
                connectionError
            } else if queue.running.isEmpty {
                emptyState("No jobs are running", symbol: "checkmark.circle")
            } else {
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
                        onStop: { panel.confirmation = .stop(job) }
                    )
                }
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading("Waiting queue", count: queue.pending.count, symbol: "list.number")
            if queue.isConnected && queue.pending.isEmpty {
                emptyState("No waiting jobs", symbol: "tray")
            } else if queue.isConnected {
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
                }
            }
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
                Text(queue.movingJobID != nil ? "Moving job to the front…" : "Stopping job…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var connectionError: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unable to read the queue")
                .font(.system(size: 12, weight: .semibold))
            Text(queue.errorMessage ?? "Check that ComfyUI is running and the address is correct.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text(queue.lastUpdated.map { "Updated \($0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US"))))" } ?? "Refreshes every 4 seconds")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Divider() }
    }

    private func sectionHeading(_ title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
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

struct SummaryTile: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("\(count)").font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum JobState {
    case running
    case pending

    var label: String { self == .running ? "Running" : "Waiting" }
    var color: Color { self == .running ? .cyan : .orange }
    var symbol: String { self == .running ? "bolt.fill" : "clock" }
}

enum QueueConfirmation {
    case prioritize(QueueJob)
    case stop(QueueJob)

    var title: String {
        switch self {
        case .prioritize: return "Prioritize this job?"
        case .stop: return "Stop this job?"
        }
    }

    var message: String {
        switch self {
        case .prioritize(let job):
            return "Move \"\(job.title)\" to the front of the waiting queue. The running job continues. This resubmits the job and changes its prompt ID."
        case .stop(let job):
            return "Stop generation for \"\(job.title)\". Waiting jobs remain queued and the next job can run."
        }
    }
}

struct JobCard: View {
    let job: QueueJob
    let state: JobState
    let progress: QueueProgress?
    let progressBridgeStatus: ProgressBridgeStatus
    let isMoving: Bool
    let isStopping: Bool
    let isActionEnabled: Bool
    let onPrioritize: (() -> Void)?
    let onStop: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if case .pending = state {
                Text(String(format: "%02d", job.position))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.color)
                    .frame(width: 28, height: 28)
                    .background(state.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.color)
                    .frame(width: 28, height: 28)
                    .background(state.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(job.title)
                HStack(spacing: 8) {
                    Text("ID \(job.shortID)")
                    Text("·")
                    Text("\(job.nodeCount) nodes")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                if case .running = state {
                    progressDetails
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 7) {
                Text(state.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(state.color.opacity(0.1), in: Capsule())
                if case .pending = state {
                    Button(action: { onPrioritize?() }) {
                        Label(isMoving ? "Working" : "Prioritize", systemImage: "arrow.up.to.line")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!isActionEnabled || isMoving)
                    .help("Run next after the current job")
                } else {
                    Button(action: { onStop?() }) {
                        Label(isStopping ? "Stopping" : "Stop", systemImage: "stop.fill")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                    .disabled(!isActionEnabled || isStopping)
                    .help("Stop this job while keeping waiting jobs")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var progressDetails: some View {
        if let progress {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.nodeTitle(for: job))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.8))
                HStack(spacing: 6) {
                    if let percent = progress.percent {
                        ProgressView(value: min(max(percent / 100, 0), 1))
                            .controlSize(.mini)
                            .frame(width: 94)
                        Text("\(Int(percent.rounded()))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    } else {
                        ProgressView().controlSize(.mini)
                        Text("Node is processing")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 5) {
                if progressBridgeStatus == .checking {
                    ProgressView().controlSize(.mini)
                }
                Text(progressStatusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
    }

    private var progressStatusText: String {
        switch progressBridgeStatus {
        case .checking: return "Fetching node progress…"
        case .available: return "No progress reported for this node yet"
        case .missing: return "Install the progress extension and restart ComfyUI"
        case .error: return "Unable to read live progress"
        }
    }
}
