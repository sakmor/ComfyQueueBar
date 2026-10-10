import AppKit
import Foundation
import SwiftUI

enum MonitoringState: Equatable {
    case checking, connected, disconnected, signInRequired, stale

    static func resolve(connected: Bool, loading: Bool, needsSignIn: Bool, lastUpdated: Date?, hasError: Bool, now: Date) -> Self {
        if needsSignIn { return .signInRequired }
        if connected {
            guard let lastUpdated, now.timeIntervalSince(lastUpdated) < 30 else { return .stale }
            return .connected
        }
        return loading && lastUpdated == nil && !hasError ? .checking : .disconnected
    }

    var label: String {
        switch self {
        case .checking: return L10n.text("Checking connection…")
        case .connected: return L10n.text("Connected")
        case .disconnected: return L10n.text("Disconnected")
        case .signInRequired: return L10n.text("Sign-in required")
        case .stale: return L10n.text("Queue status out of date")
        }
    }

    func badge(count: Int) -> String {
        switch self {
        case .connected: return count > 99 ? "99+" : String(count)
        case .checking: return "…"
        case .signInRequired: return "!"
        case .disconnected, .stale: return "—"
        }
    }

    static func requiresSignIn(_ error: Error) -> Bool {
        if case GPUTWError.signInRequired = error { return true }
        if case QueueError.serverStatus(let code, _) = error { return code == 401 || code == 403 }
        return false
    }
}

enum PairedPortIssue: Equatable {
    case portNotEnabled
    case signInRequired
    case unavailable

    static func classify(_ error: Error) -> Self {
        if case QueueError.serverStatus(let status, _) = error, status == 404 {
            return .portNotEnabled
        }
        if MonitoringState.requiresSignIn(error) {
            return .signInRequired
        }
        return .unavailable
    }
}

enum ConnectionAddress {
    static func normalize(_ address: String) throws -> String {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value), let host = parts.host, !host.isEmpty,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil else { throw QueueError.invalidEndpoint }
        if let url = parts.url, let origin = GPUTWAddress.serviceOrigin(url) { return origin.absoluteString }
        parts.query = nil; parts.fragment = nil
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw QueueError.invalidEndpoint }
        return url.absoluteString
    }

    static func port(_ endpoint: String) -> String {
        guard let url = URL(string: endpoint) else { return "—" }
        if GPUTWAddress.serviceOrigin(url) != nil { return url.host?.split(separator: "-").first.map(String.init) ?? "—" }
        return String(url.port ?? (url.scheme == "https" ? 443 : 80))
    }

    static func portLabel(_ endpoint: String) -> String { L10n.text("Port %@", port(endpoint)) }
}

struct ConnectionInspection {
    let endpoint: String
    let checkedAt: Date
    let running: [QueueJob]
    let pending: [QueueJob]
    let completed: [CompletedJob]
    let failures: [FailedJob]
    let historyAvailable: Bool
    var isIdle: Bool { running.isEmpty && pending.isEmpty }
}

@MainActor
enum ConnectionInspector {
    static func inspectQueue(_ address: String, client: ComfyHTTPClient? = nil, timeout: TimeInterval = 3) async throws -> ConnectionInspection {
        try Task.checkCancellation()
        let endpoint = try ConnectionAddress.normalize(address)
        let client = client ?? .shared
        var parts = URLComponents(string: endpoint)!
        parts.path += "/queue"
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await client.data(for: request)
        guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            throw QueueError.serverStatus((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        guard let queue = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ComfyQueuePayload.isValid(queue) else { throw QueueError.invalidResponse }
        return ConnectionInspection(endpoint: endpoint, checkedAt: Date(),
            running: QueueViewModel.parseJobs(queue["queue_running"]), pending: QueueViewModel.parseJobs(queue["queue_pending"]),
            completed: [], failures: [], historyAvailable: false)
    }

    static func inspect(_ address: String, client: ComfyHTTPClient? = nil) async throws -> ConnectionInspection {
        try Task.checkCancellation()
        let endpoint = try ConnectionAddress.normalize(address)
        let client = client ?? .shared
        func read(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
            var parts = URLComponents(string: endpoint)!
            parts.path += "/" + path
            parts.queryItems = query.isEmpty ? nil : query
            var request = URLRequest(url: parts.url!)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await client.data(for: request)
            guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
                throw QueueError.serverStatus((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueueError.invalidResponse }
            return object
        }
        let queue = try await read("queue")
        guard ComfyQueuePayload.isValid(queue) else { throw QueueError.invalidResponse }
        let checkedAt = Date()
        var history: [String: Any] = [:]
        var historyAvailable = false
        do {
            history = try await read("history", query: [URLQueryItem(name: "max_items", value: "20")])
            historyAvailable = true
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // A queue can be healthy while history is unsupported or temporarily unavailable.
        }
        try Task.checkCancellation()
        return ConnectionInspection(endpoint: endpoint, checkedAt: checkedAt,
            running: QueueViewModel.parseJobs(queue["queue_running"]), pending: QueueViewModel.parseJobs(queue["queue_pending"]),
            completed: CompletionHistory.parse(history, now: Date(), maxAge: nil, limit: 3, title: QueueViewModel.jobTitle),
            failures: Array(HistoryDetails.failures(history, title: QueueViewModel.jobTitle).prefix(1)),
            historyAvailable: historyAvailable)
    }
}

@MainActor
final class ConnectionReviewModel: ObservableObject {
    @Published private(set) var inspection: ConnectionInspection?
    @Published private(set) var pairedInspection: ConnectionInspection?
    @Published private(set) var pairedEndpoint: String?
    @Published private(set) var pairedIssue: PairedPortIssue?
    @Published private(set) var selectedEndpoint: String?
    @Published private(set) var error: String?
    @Published private(set) var errorIssue: PairedPortIssue?
    @Published private(set) var checking = false
    @Published private(set) var checkingPaired = false
    private var revision = UUID()

    func cancel() {
        revision = UUID(); inspection = nil; pairedInspection = nil; pairedEndpoint = nil; pairedIssue = nil
        selectedEndpoint = nil; error = nil; errorIssue = nil; checking = false; checkingPaired = false
    }

    func inspect(_ address: String) async {
        guard !Task.isCancelled else { return }
        let token = UUID(); revision = token
        inspection = nil; pairedInspection = nil; pairedEndpoint = nil; pairedIssue = nil; error = nil; errorIssue = nil
        selectedEndpoint = address; checking = true; checkingPaired = false
        defer { if revision == token { checking = false } }
        do {
            let result = try await ConnectionInspector.inspect(address)
            guard revision == token, !Task.isCancelled else { return }
            inspection = result
            if result.isIdle, let url = URL(string: result.endpoint),
               let paired = GPUTWAddress.pairedServiceOrigin(url) {
                pairedEndpoint = paired.absoluteString
                checkingPaired = true
                do {
                    let pairedResult = try await ConnectionInspector.inspectQueue(paired.absoluteString)
                    guard revision == token, !Task.isCancelled else { return }
                    pairedInspection = pairedResult
                } catch is CancellationError {
                    return
                } catch {
                    guard revision == token, !Task.isCancelled else { return }
                    pairedIssue = PairedPortIssue.classify(error)
                }
                if revision == token { checkingPaired = false }
            }
        } catch {
            guard revision == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            if let url = URL(string: address), GPUTWAddress.serviceOrigin(url) != nil {
                errorIssue = PairedPortIssue.classify(error)
            }
        }
    }
}

@MainActor
final class ConnectionReviewWindow: NSObject, NSWindowDelegate {
    static let shared = ConnectionReviewWindow()
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private let model = ConnectionReviewModel()
    private var onConfirm: ((String) -> Void)?
    private var onOpenAlternative: ((String) -> Void)?

    func open(address: String, onConfirm: @escaping (String) -> Void, onOpenAlternative: @escaping (String) -> Void = { _ in }) {
        close()
        self.onConfirm = onConfirm
        self.onOpenAlternative = onOpenAlternative
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("Confirm monitoring server")
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentViewController = NSHostingController(rootView: ConnectionReviewView(address: address, model: model,
            refresh: { [weak self] in self?.inspect(self?.model.selectedEndpoint ?? address) }, cancel: { [weak self] in self?.close() },
            reviewPaired: { [weak self] in self?.inspect($0) },
            openPaired: { [weak self] in self?.onOpenAlternative?($0) },
            confirm: { [weak self] in self?.confirm() }))
        self.window = window
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        inspect(address)
    }

    private func inspect(_ address: String) {
        task?.cancel()
        task = Task { await model.inspect(address) }
    }

    private func confirm() {
        guard let inspection = model.inspection, !model.checking else { return }
        let callback = onConfirm
        close()
        callback?(inspection.endpoint)
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        task?.cancel(); task = nil; model.cancel(); onConfirm = nil; onOpenAlternative = nil
        window?.contentViewController = nil; window = nil
    }
}

struct ConnectionReviewView: View {
    let address: String
    @ObservedObject var model: ConnectionReviewModel
    let refresh: () -> Void
    let cancel: () -> Void
    let reviewPaired: (String) -> Void
    let openPaired: (String) -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let selectedAddress = model.selectedEndpoint ?? address
            Text(L10n.text("Confirm monitoring server")).font(.title2.bold())
            Text(ConnectionAddress.portLabel(selectedAddress)).font(.title3.monospacedDigit().bold())
            Text(selectedAddress).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.checking {
                        HStack { ProgressView().controlSize(.small); Text(L10n.text("Reading queue and recent history…")) }
                    } else if let error = model.error {
                        Label(L10n.text("Unable to read the queue"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        if let issue = model.errorIssue,
                           let endpoint = model.selectedEndpoint {
                            let port = ConnectionAddress.port(endpoint)
                            Text(pairedIssueMessage(issue, port: port)).font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(error).font(.callout)
                        }
                        if let endpoint = model.selectedEndpoint, let url = URL(string: endpoint),
                           GPUTWAddress.serviceOrigin(url) != nil {
                            Button(L10n.text("Open GPUtw dashboard")) { openPaired(GPUTWAddress.dashboard.absoluteString) }
                                .controlSize(.small)
                        }
                    } else if let inspection = model.inspection {
                        ConnectionInspectionCard(inspection: inspection)
                    }
                    if let pairedEndpoint = model.pairedEndpoint {
                        pairedPortCard(endpoint: pairedEndpoint, inspection: model.pairedInspection)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text(L10n.text("Your current monitoring server changes only after you confirm.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(L10n.text("Refresh details"), action: refresh).disabled(model.checking)
                Spacer()
                Button(L10n.text("Monitor this server"), action: confirm).buttonStyle(.borderedProminent)
                    .disabled(model.inspection == nil || model.checking)
            }
        }.padding(22).frame(width: 480, height: 660)
    }

    @ViewBuilder
    private func pairedPortCard(endpoint: String, inspection: ConnectionInspection?) -> some View {
        let port = ConnectionAddress.port(endpoint)
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if model.checkingPaired {
                HStack { ProgressView().controlSize(.small); Text(L10n.text("Checking Port %@…", port)) }
                    .font(.callout).foregroundStyle(.secondary)
            } else if let inspection {
                if inspection.isIdle {
                    Label(L10n.text("No queued work on Port %@.", port), systemImage: "arrow.left.arrow.right")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Label(L10n.text("Found work on Port %@.", port), systemImage: "arrow.left.arrow.right")
                        .font(.callout.weight(.semibold))
                    Text(L10n.text("Running %@ · Waiting %@", String(inspection.running.count), String(inspection.pending.count)))
                        .font(.caption).foregroundStyle(.secondary)
                    if let job = inspection.running.first ?? inspection.pending.first {
                        Text(job.title).font(.callout).lineLimit(2).help(job.title)
                    }
                }
                Button(L10n.text("Review Port %@", port)) { reviewPaired(endpoint) }
                    .controlSize(.small)
            } else if let issue = model.pairedIssue {
                Label(pairedIssueMessage(issue, port: port), systemImage: "arrow.left.arrow.right")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                switch issue {
                case .portNotEnabled, .signInRequired:
                    Button(L10n.text("Open GPUtw dashboard")) { openPaired(GPUTWAddress.dashboard.absoluteString) }
                        .controlSize(.small)
                case .unavailable:
                    Button(L10n.text("Review Port %@", port)) { reviewPaired(endpoint) }
                        .controlSize(.small)
                }
            } else {
                Label(L10n.text("Could not check GPUtw port %@. Check your connection and retry.", port),
                      systemImage: "arrow.left.arrow.right")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Review Port %@", port)) { reviewPaired(endpoint) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func pairedIssueMessage(_ issue: PairedPortIssue, port: String) -> String {
        switch issue {
        case .portNotEnabled: return L10n.text("GPUtw returned 404 on port %@. Enable it as an HTTP port in Network Ports, then open it from the dashboard's Other ports menu.", port)
        case .signInRequired: return L10n.text("Port %@ needs an owner session. Open it from the GPUtw dashboard's Other ports menu.", port)
        case .unavailable: return L10n.text("Could not check GPUtw port %@. Check your connection and retry.", port)
        }
    }
}

struct ConnectionInspectionCard: View {
    let inspection: ConnectionInspection
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                count(L10n.text("Running"), inspection.running.count)
                count(L10n.text("Waiting"), inspection.pending.count)
            }
            Text(L10n.text("Checked %@", inspection.checkedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(L10n.locale))))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Counts show ComfyUI jobs, not GPU utilization.")).font(.caption).foregroundStyle(.secondary)
            if inspection.isIdle {
                Label(L10n.text("This queue is empty. If you expect a running job, check the port and recent work below."), systemImage: "info.circle")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(10).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(inspection.running.prefix(2)) { job in
                Label(job.title, systemImage: "waveform.path").font(.callout).lineLimit(2).help(job.title)
            }
            Divider()
            Text(L10n.text("Recent successful jobs")).font(.headline)
            if !inspection.historyAvailable {
                Text(L10n.text("History could not be read. Recent work is unknown.")).foregroundStyle(.orange)
            } else if inspection.completed.isEmpty {
                Text(L10n.text("No successful jobs in the latest 20 history records.")).foregroundStyle(.secondary)
            } else {
                ForEach(inspection.completed) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title).font(.callout).lineLimit(2).help(job.title)
                        Text(job.finishedAt.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) }
                             ?? L10n.text("Completion time unavailable")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let failure = inspection.failures.first {
                Divider()
                Text(L10n.text(failure.interrupted ? "Interrupted" : "Failed")).font(.headline).foregroundStyle(.orange)
                Text(failure.title).font(.callout).lineLimit(2).help(failure.title)
            }
        }.font(.callout)
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(value)).font(.title2.monospacedDigit().bold())
        }
    }
}
